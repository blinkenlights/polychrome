defmodule Octopus.Apps.PixelFun do
  use Octopus.App, category: :animation

  alias Octopus.Canvas
  alias Octopus.Protobuf.InputEvent
  alias Octopus.Apps.PixelFun.Program

  @width 8 * get_screen_count() + 18 * (get_screen_count() - 1)
  @height 8

  @center_x @width / 2 + 0.5
  @center_y @height / 2 + 0.5

  @functions [
    "sin(t-hypot(x-#{@center_x},y-3.5))",
    "2*fract((0.5*t-x*0.01)*0.5+hypot(x-#{@center_x},y-#{@center_y}))-1.0",
    "sin(t-x/2-y/2)",
    "sin(t+hypot(x-#{@center_x},y-#{@center_y}))",
    "sin(t+x/2-y/2)",
    "cos(x+sin(t))-sin(y-cos(t)*0.5)"
  ]

  defmodule State do
    defstruct [
      :canvas,
      :program,
      :source,
      :easing_interval,
      :invert_colors,
      :colors,
      :last_colors,
      :target_colors,
      :lerp_time,
      :translate_scale,
      :rotate_scale,
      :zoom_scale,
      :color_interval,
      :cycle_functions,
      :cycle_functions_interval,
      :functions,
      :pivot,
      :offset,
      :move
    ]
  end

  def name(), do: "Pixel Fun"

  def config_schema() do
    %{
      program: {"Program", :string, %{default: Enum.at(@functions, 0)}},
      easing_interval: {"Afterglow", :int, %{default: 50, min: 0, max: 500}},
      color_interval: {"Color change Interval (s)", :float, %{default: 5, min: 1, max: 20}},
      invert_colors: {"Invert Colors", :boolean, %{default: false}},
      translate_scale: {"Translate Scale", :float, %{default: 5, min: 0, max: 20}},
      rotate_scale: {"Rotation Scale", :float, %{default: 0.1, min: 0, max: 4}},
      zoom_scale: {"Zoom Scale", :float, %{default: 2, min: 0, max: 10}},
      cycle_functions: {"Cycle Functions", :boolean, %{default: false}},
      cycle_functions_interval:
        {"Cycle Functions Interval (s)", :float, %{default: 30, min: 1, max: 60 * 60}}
    }
  end

  def get_config(state) do
    %{
      program: state.source,
      easing_interval: state.easing_interval,
      invert_colors: state.invert_colors,
      color_interval: state.color_interval,
      cycle_functions: state.cycle_functions,
      cycle_functions_interval: state.cycle_functions_interval,
      translate_scale: state.translate_scale,
      rotate_scale: state.rotate_scale,
      zoom_scale: state.zoom_scale
    }
  end

  def init(config) do
    canvas = Canvas.new(@width, @height)

    {:ok, program} = config.program |> Program.parse()

    :timer.send_interval((1000 / 60) |> trunc(), :tick)
    :timer.send_interval(trunc(config.color_interval * 1000), :update_colors)

    Process.send_after(self(), :cycle_functions, trunc(config.cycle_functions_interval * 1000))

    functions =
      @functions
      |> Enum.map(fn source -> {source, Program.parse(source) |> elem(1)} end)
      |> Stream.cycle()

    {:ok,
     %State{
       canvas: canvas,
       program: program,
       source: config.program,
       easing_interval: config.easing_interval,
       invert_colors: config.invert_colors,
       colors: generate_random_colors(),
       last_colors: generate_random_colors(),
       target_colors: generate_random_colors(),
       lerp_time: config.color_interval,
       color_interval: config.color_interval,
       cycle_functions: config.cycle_functions,
       cycle_functions_interval: config.cycle_functions_interval,
       translate_scale: config.translate_scale,
       rotate_scale: config.rotate_scale,
       zoom_scale: config.zoom_scale,
       functions: functions,
       pivot: {@center_x, @center_y},
       offset: {0, 0},
       move: {0, 0}
     }}
  end

  def handle_config(
        %{
          program: program,
          easing_interval: easing_interval,
          invert_colors: invert_colors,
          cycle_functions: cycle_functions,
          translate_scale: translate_scale,
          rotate_scale: rotate_scale,
          zoom_scale: zoom_scale
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
         easing_interval: easing_interval,
         invert_colors: invert_colors,
         cycle_functions: cycle_functions,
         translate_scale: translate_scale,
         rotate_scale: rotate_scale,
         zoom_scale: zoom_scale
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

  def handle_info(:cycle_functions, %State{cycle_functions: true, functions: functions} = state) do
    [{source, function}] = Enum.take(functions, 1)
    functions = Stream.drop(functions, 1)

    {:noreply, %State{state | functions: functions, program: function, source: source}}
  end

  def handle_info(:cycle_functions, %State{} = state) do
    Process.send_after(self(), :cycle_functions, trunc(state.cycle_functions_interval * 1000))
    {:noreply, state}
  end

  def handle_info(:tick, %State{} = state) do
    state = lerp_toward_target_colors(state)

    {offset_x, offset_y} = state.offset
    offset_x = offset_x + elem(state.move, 0) * 25 / 60
    offset_y = offset_y + elem(state.move, 1) * 25 / 60

    canvas = state |> render()

    canvas
    |> Canvas.to_frame(drop: true)
    |> Map.put(:easing_interval, state.easing_interval)
    |> send_frame()

    {:noreply, %State{state | canvas: canvas, offset: {offset_x, offset_y}}}
  end

  def handle_input(%InputEvent{type: axis, value: value}, %State{move: {_, y}} = state)
      when axis in [:AXIS_X_1, :AXIS_X_2] do
    {:noreply, %State{state | move: {-value, y}}}
  end

  def handle_input(%InputEvent{type: axis, value: value}, %State{move: {x, _}} = state)
      when axis in [:AXIS_Y_1, :AXIS_Y_2] do
    {:noreply, %State{state | move: {x, -value}}}
  end

  def handle_input(_, state), do: {:noreply, state}

  defp render(%State{canvas: canvas, program: program} = state) do
    {seconds, micros} = Time.utc_now() |> Time.to_seconds_after_midnight()
    seconds = seconds + micros / 1_000_000

    dt = 1 / 60

    offset_x =
      elem(state.offset, 0) +
        :math.sin(0.3 + seconds * 0.17) * state.translate_scale + elem(state.move, 0) * 100 * dt

    offset_y =
      elem(state.offset, 1) +
        :math.cos(0.7 + seconds * 0.05) * state.translate_scale + elem(state.move, 1) * 100 * dt

    {pivot_x, pivot_y} = state.pivot

    zoom =
      if state.zoom_scale == 0 do
        1.0
      else
        (:math.sin(seconds * 0.1) * 0.5 + 0.5) * state.zoom_scale
      end

    rotation = seconds * state.rotate_scale

    {color_a, color_b} = state.colors

    colors =
      if state.invert_colors do
        {color_b, color_a}
      else
        {color_a, color_b}
      end

    for i <- 0..(@width * @height - 1), into: canvas do
      x = rem(i, @width)
      y = div(i, @width)

      x_translated = x - pivot_x
      y_translated = y - pivot_y

      x_rotated = x_translated * :math.cos(rotation) - y_translated * :math.sin(rotation)
      y_rotated = x_translated * :math.sin(rotation) + y_translated * :math.cos(rotation)

      x_scaled = x_rotated * zoom
      y_scaled = y_rotated * zoom

      x_new = x_scaled + pivot_x - offset_x
      y_new = y_scaled + pivot_y - offset_y

      {{x, y}, pixels(program, x_new, y_new, i, seconds, colors)}
    end
  end

  @default_env %{~c"pi" => :math.pi(), ~c"tau" => :math.pi() * 2}

  defp pixels(expr, x, y, i, t, {color_a, color_b}) do
    env = [%{~c"x" => x, ~c"y" => y, ~c"i" => i, ~c"t" => t}, @default_env]

    value =
      expr
      |> Program.eval(env)
      |> max(-1.0)
      |> min(1.0)

    interpolate_colors(color_a, color_b, value)
  end

  defp interpolate_colors({r1, g1, b1}, {r2, g2, b2}, value) do
    cond do
      value > 0 -> [r1 * value, g1 * value, b1 * value]
      value < 0 -> [r2 * -value, g2 * -value, b2 * -value]
      true -> [0, 0, 0]
    end
    |> Enum.map(&Kernel.trunc/1)
    |> List.to_tuple()
  end

  defp lerp_toward_target_colors(%State{} = state) do
    current_time = max(state.color_interval - state.lerp_time, 0)
    t = current_time / state.color_interval
    lerp_time = max(state.lerp_time - 1 / 60, 0)

    {last_a, last_b} = state.last_colors
    {target_a, target_b} = state.target_colors
    new_a = lerp_rgb(last_a, target_a, t)
    new_b = lerp_rgb(last_b, target_b, t)

    %State{state | colors: {new_a, new_b}, lerp_time: lerp_time}
  end

  defp lerp_rgb({r1, g1, b1}, {r2, g2, b2}, value) do
    hsl_a = Chameleon.RGB.new(r1, g1, b1) |> Chameleon.convert(Chameleon.HSL)
    hsl_b = Chameleon.RGB.new(r2, g2, b2) |> Chameleon.convert(Chameleon.HSL)
    h = lerp(hsl_a.h, hsl_b.h, value) |> trunc()
    s = lerp(hsl_a.s, hsl_b.s, value) |> trunc()
    l = lerp(hsl_a.l, hsl_b.l, value) |> trunc()

    %Chameleon.RGB{r: r, g: g, b: b} =
      Chameleon.HSL.new(h, s, l)
      |> Chameleon.convert(Chameleon.RGB)

    {r, g, b}
  end

  defp lerp(a, b, t) do
    (1 - t) * a + t * b
  end

  defp generate_random_colors do
    hue_a = :rand.uniform(360) - 1
    hue_b = Integer.mod(hue_a + 90 + :rand.uniform(180) - 1, 360)
    sat_a = 70 + :rand.uniform(29)
    sat_b = 70 + :rand.uniform(29)
    hsv_a = Chameleon.HSV.new(hue_a, sat_a, 100)
    hsv_b = Chameleon.HSV.new(hue_b, sat_b, 100)
    %Chameleon.RGB{r: r1, g: g1, b: b1} = Chameleon.convert(hsv_a, Chameleon.RGB)
    %Chameleon.RGB{r: r2, g: g2, b: b2} = Chameleon.convert(hsv_b, Chameleon.RGB)
    {{r1, g1, b1}, {r2, g2, b2}}
  end
end
