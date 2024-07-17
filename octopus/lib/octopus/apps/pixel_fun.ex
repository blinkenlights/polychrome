defmodule Octopus.Apps.PixelFun do
  use Octopus.App, category: :animation
  use Octopus.Params, prefix: :pixelfun

  require Logger
  alias Octopus.Canvas
  alias Octopus.Protobuf.{InputEvent, SoundToLightControlEvent}
  alias Octopus.Apps.PixelFun.Program

  @fps 60
  @frame_time_ms trunc(1000 / @fps)

  defmodule State do
    defstruct [
      :program,
      :source,
      :invert_colors,
      :colors,
      :last_colors,
      :target_colors,
      :lerp_time,
      :lerp_over_black,
      :translate_scale,
      :rotate_scale,
      :zoom_scale,
      :color_interval,
      :cycle_functions,
      :cycle_functions_interval,
      :offset,
      :move,
      :input,
      :audio_input,
      :seconds
    ]
  end

  def name(), do: "Pixel Fun"

  defdelegate installation, to: Octopus

  def center_x, do: installation().center_x()
  def center_y, do: installation().center_y()

  def config_schema() do
    %{
      program: {"Program", :string, %{default: "sin(t*2+i)*y-cos(t*2-i)*x"}},
      color_interval: {"Color change Interval (s)", :float, %{default: 5, min: 1, max: 20}},
      invert_colors: {"Invert Colors", :boolean, %{default: false}},
      translate_scale: {"Translate Scale", :float, %{default: 5, min: 0, max: 20}},
      rotate_scale: {"Rotation Scale", :float, %{default: 0.1, min: 0, max: 4}},
      zoom_scale: {"Zoom Scale", :float, %{default: 2, min: 0, max: 10}},
      cycle_functions: {"Cycle Functions", :boolean, %{default: false}},
      cycle_functions_interval:
        {"Cycle Functions Interval (s)", :float, %{default: 30, min: 1, max: 60 * 60}},
      input: {"Input", :boolean, %{default: false}},
      lerp_over_black: {"Lerp over black", :boolean, %{default: true}}
    }
  end

  def get_config(state) do
    %{
      program: state.source,
      invert_colors: state.invert_colors,
      color_interval: state.color_interval,
      cycle_functions: state.cycle_functions,
      cycle_functions_interval: state.cycle_functions_interval,
      translate_scale: state.translate_scale,
      rotate_scale: state.rotate_scale,
      zoom_scale: state.zoom_scale,
      input: state.input,
      lerp_over_black: state.lerp_over_black
    }
  end

  def init(config) do
    # canvas = Canvas.new(installation().wid(), @width, @height)
    {:ok, program} = config.program |> Program.parse()

    :timer.send_interval(@frame_time_ms, :tick)
    Process.send_after(self(), :update_colors, param(:color_interval_ms, 5000))
    # Process.send_after(self(), :cycle_functions, trunc(config.cycle_functions_interval * 1000))

    {seconds, micros} = NaiveDateTime.utc_now() |> NaiveDateTime.to_gregorian_seconds()
    seconds = seconds + micros / 1_000_000

    {:ok,
     %State{
       program: program,
       source: config.program,
       invert_colors: config.invert_colors,
       colors: generate_random_colors(),
       last_colors: generate_random_colors(),
       target_colors: generate_random_colors(),
       lerp_time: config.color_interval,
       lerp_over_black: config.lerp_over_black,
       color_interval: config.color_interval,
       cycle_functions: config.cycle_functions,
       cycle_functions_interval: config.cycle_functions_interval,
       translate_scale: config.translate_scale,
       rotate_scale: config.rotate_scale,
       zoom_scale: config.zoom_scale,
       # pivot: {@center_x, @center_y},
       offset: {0, 0},
       move: {0, 0},
       input: config.input,
       audio_input: %{low: 0.0, mid: 0.0, high: 0.0},
       seconds: seconds
     }}
  end

  def handle_config(
        %{
          program: program,
          invert_colors: invert_colors,
          cycle_functions: cycle_functions,
          translate_scale: translate_scale,
          rotate_scale: rotate_scale,
          zoom_scale: zoom_scale,
          lerp_over_black: lerp_over_black
        },
        %State{} = state
      ) do
    source = program

    program =
      case Program.parse(program) do
        {:ok, program} -> program
        _ -> 0
      end

    {:noreply,
     %State{
       state
       | program: program,
         source: source,
         invert_colors: invert_colors,
         cycle_functions: cycle_functions,
         translate_scale: translate_scale,
         rotate_scale: rotate_scale,
         zoom_scale: zoom_scale,
         lerp_over_black: lerp_over_black
     }}
  end

  def update_program(pid, program) do
    program =
      case Program.parse(program) do
        {:ok, program} -> program
        _ -> 0
      end

    GenServer.cast(pid, {:update_program, program})
  end

  def handle_cast({:update_program, program}, %State{} = state) do
    {:noreply, %{state | program: program}}
  end

  def handle_info(:update_colors, %State{} = state) do
    colors = generate_random_colors()

    {:noreply,
     %State{
       state
       | last_colors: state.colors,
         target_colors: colors,
         lerp_time: state.color_interval
     }}
  end

  def handle_info(:tick, %State{} = state) do
    state = lerp_toward_target_colors(state)

    {offset_x, offset_y} = state.offset
    offset_x = offset_x + elem(state.move, 0) * 5 / 60 * 0
    offset_y = offset_y + elem(state.move, 1) * 5 / 60 * 0

    state = %State{
      state
      | offset: {offset_x, offset_y},
        seconds: state.seconds + 1 / @fps * param(:time_scale, 1.0)
    }

    canvas = state |> render()

    canvas
    |> Canvas.to_frame(easing_interval: trunc(param(:easing_interval, 200)))
    |> send_frame()

    {:noreply, state}
  end

  def handle_input(%SoundToLightControlEvent{bass: low, mid: mid, high: high}, state) do
    {:noreply, %State{state | audio_input: %{low: low, mid: mid, high: high}}}
  end

  def handle_input(
        %InputEvent{type: axis, value: value},
        %State{move: {_, y}, input: true} = state
      )
      when axis in [:AXIS_X_1, :AXIS_X_2] do
    {:noreply, %State{state | move: {-value, y}}}
  end

  def handle_input(
        %InputEvent{type: axis, value: value},
        %State{move: {x, _}, input: true} = state
      )
      when axis in [:AXIS_Y_1, :AXIS_Y_2] do
    {:noreply, %State{state | move: {x, -value}}}
  end

  def handle_input(_, state), do: {:noreply, state}

  defp render(%State{program: program} = state) do
    offset_x = :math.sin(0.3 + state.seconds * param(:translate_speed, 0.0))
    offset_y = :math.cos(0.7 + state.seconds * param(:translate_speed, 0.0))

    zoom = (:math.sin(state.seconds * 0.1) * 0.5 + 0.5) * param(:zoom_scale, 1.0)

    rotation = state.seconds * param(:rotate_speed, 0.0)

    {color_a, color_b} = state.colors

    colors =
      if state.invert_colors do
        {color_b, color_a}
      else
        {color_a, color_b}
      end

    lerp_fn =
      if state.lerp_over_black, do: &interpolate_colors_with_black/3, else: &interpolate_colors/3

    installation().panels()
    |> Enum.map(fn panel ->
      for {{x, y}, i} <- Enum.with_index(panel), into: Canvas.new(8, 8) do
        local_x = rem(i, 8)
        local_y = div(i, 8)

        x_translated = x - offset_x - center_x()
        y_translated = y - offset_y - center_y()

        x_rotated = x_translated * :math.cos(rotation) - y_translated * :math.sin(rotation)
        y_rotated = x_translated * :math.sin(rotation) + y_translated * :math.cos(rotation)

        x_scaled = x_rotated * zoom
        y_scaled = y_rotated * zoom

        {{local_x, local_y},
         pixels(
           program,
           x_scaled,
           y_scaled,
           i,
           state.seconds,
           state.audio_input.low,
           state.audio_input.mid,
           state.audio_input.high,
           colors,
           lerp_fn
         )}
      end
    end)
    |> Enum.reduce(&Canvas.join(&2, &1))
  end

  @default_env %{~c"pi" => :math.pi(), ~c"tau" => :math.pi() * 2}

  defp pixels(expr, x, y, i, t, l, m, h, {color_a, color_b}, lerp_fn) do
    env = [
      %{~c"x" => x, ~c"y" => y, ~c"i" => i, ~c"t" => t, ~c"l" => l, ~c"m" => m, ~c"h" => h},
      @default_env
    ]

    value =
      expr
      |> Program.eval(env)
      |> max(-1.0)
      |> min(1.0)

    lerp_fn.(color_a, color_b, value)
  end

  defp interpolate_colors_with_black(%Chameleon.HSV{} = a, %Chameleon.HSV{} = b, value) do
    rgb =
      cond do
        value > 0 ->
          %Chameleon.HSV{
            a
            | s: param(:saturation_percent, 70),
              v: trunc(param(:value_percent, 100) * value)
          }

        value < 0 ->
          %Chameleon.HSV{
            b
            | s: param(:saturation_percent, 70),
              v: trunc(param(:value_percent, 100) * -value)
          }

        true ->
          %Chameleon.HSV{h: 0, s: 0, v: 0}
      end
      |> Chameleon.convert(Chameleon.RGB)

    %Chameleon.RGB{r: r, g: g, b: b} = rgb
    {r, g, b}
  end

  defp interpolate_colors(%Chameleon.HSV{} = a, %Chameleon.HSV{} = b, value) do
    %Chameleon.RGB{r: a_r, g: a_g, b: a_b} = Chameleon.convert(a, Chameleon.RGB)
    %Chameleon.RGB{r: b_r, g: b_g, b: b_b} = Chameleon.convert(b, Chameleon.RGB)

    r = lerp(a_r, b_r, value) |> trunc |> min(255) |> max(0)
    g = lerp(a_g, b_g, value) |> trunc |> min(255) |> max(0)
    b = lerp(a_b, b_b, value) |> trunc |> min(255) |> max(0)

    hsv = Chameleon.RGB.new(r, g, b) |> Chameleon.convert(Chameleon.HSV)

    hsv = %Chameleon.HSV{
      hsv
      | s: param(:saturation_percent, 70),
        v: trunc(param(:value_percent, 100) * -value) |> min(100) |> max(0)
    }

    %Chameleon.RGB{r: r, g: g, b: b} = Chameleon.convert(hsv, Chameleon.RGB)
    {r, g, b}
  end

  defp lerp_toward_target_colors(%State{} = state) do
    current_time = max(state.color_interval - state.lerp_time, 0)
    t = current_time / state.color_interval
    lerp_time = max(state.lerp_time - 1 / @fps, 0)

    {last_a, last_b} = state.last_colors
    {target_a, target_b} = state.target_colors
    new_a = lerp_rgb(last_a, target_a, t)
    new_b = lerp_rgb(last_b, target_b, t)

    %State{state | colors: {new_a, new_b}, lerp_time: lerp_time}
  end

  defp lerp_rgb(a, b, value) do
    a_rgb = Chameleon.convert(a, Chameleon.RGB)
    b_rgb = Chameleon.convert(b, Chameleon.RGB)

    r = lerp(a_rgb.r, b_rgb.r, value) |> trunc()
    g = lerp(a_rgb.g, b_rgb.g, value) |> trunc()
    b = lerp(a_rgb.b, b_rgb.b, value) |> trunc()

    Chameleon.RGB.new(r, g, b)
    |> Chameleon.convert(Chameleon.HSV)
  end

  defp lerp_hsv(a, b, value) do
    hsl_a = Chameleon.convert(a, Chameleon.HSL)
    hsl_b = Chameleon.convert(b, Chameleon.HSL)
    h = lerp(hsl_a.h, hsl_b.h, value) |> trunc()
    s = lerp(hsl_a.s, hsl_b.s, value) |> trunc()
    l = lerp(hsl_a.l, hsl_b.l, value) |> trunc()

    Chameleon.HSL.new(h, s, l)
    |> Chameleon.convert(Chameleon.HSV)
  end

  defp lerp(a, b, t) do
    (1 - t) * a + t * b
  end

  defp generate_random_colors do
    hue_a = :rand.uniform(360) - 1
    hue_b = Integer.mod(hue_a + 90 + :rand.uniform(180) - 1, 360)
    sat_a = param(:saturation_percent, 70)
    sat_b = param(:saturation_percent, 70)
    hsv_a = Chameleon.HSV.new(hue_a, sat_a, 100)
    hsv_b = Chameleon.HSV.new(hue_b, sat_b, 100)
    {hsv_a, hsv_b}
  end
end
