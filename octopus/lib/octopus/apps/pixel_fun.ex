defmodule Octopus.Apps.PixelFun do
  use Octopus.App

  alias Octopus.Canvas
  alias Octopus.Apps.PixelFun.Program

  @width 8 * 10 + 9 * 18
  @height 8

  @functions [
    "sin(t-hypot(x-3.5,y-3.5))",
    "2*fract((0.5*t-x*0.01)*0.5+hypot(x-3.5,y-3.5))-1.0",
    "sin(t-x/2-y/2)",
    "sin(t+hypot(x-3.5,y-3.5))",
    "sin(t+x/2-y/2)",
    "sin(t+x*y)",
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
      :random_colors,
      :lerp_time,
      :color_interval,
      :cycle_functions,
      :cycle_functions_interval,
      :functions
    ]
  end

  def name(), do: "Pixel Fun"

  def config_schema() do
    %{
      program: {"Program", :string, %{default: "sin(t-hypot(x-3.5,y-3.5))"}},
      easing_interval: {"Afterglow", :int, %{default: 50, min: 0, max: 500}},
      color_interval: {"Color change Interval (s)", :float, %{default: 5, min: 1, max: 20}},
      invert_colors: {"Invert Colors", :boolean, %{default: false}},
      random_colors: {"Random Colors", :boolean, %{default: true}},
      cycle_functions: {"Cycle Functions", :boolean, %{default: true}},
      cycle_functions_interval:
        {"Cycle Functions Interval (s)", :float, %{default: 30, min: 1, max: 60 * 60}},
      colors: {
        "Colors",
        :select,
        %{
          default: 0,
          options: [
            {"Camp", {[0x3F, 0xFF, 0x21], [0xFB, 0x48, 0xC4]}},
            {"Mac Paint", {[0x8B, 0xC8, 0xFE], [0x05, 0x1B, 0x2C]}},
            {"Bitbee", {[0x29, 0x2B, 0x30], [0xCF, 0xAB, 0x4A]}},
            {"Gato Roboto - Starboard", {[0x0A, 0x2E, 0x44], [0xFC, 0xFF, 0xCC]}},
            {"French Fries", {[0xFF, 0x0F, 0x0F], [0xFF, 0xDF, 0x0F]}}
          ]
        }
      }
    }
  end

  def get_config(state) do
    %{
      program: state.source,
      easing_interval: state.easing_interval,
      invert_colors: state.invert_colors,
      colors: state.colors,
      random_colors: state.random_colors,
      color_interval: state.color_interval,
      cycle_functions: state.cycle_functions,
      cycle_functions_interval: state.cycle_functions_interval
    }
  end

  def init(_args) do
    canvas = Canvas.new(@width, @height)

    config = config_schema() |> default_config()
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
       last_colors: config.colors,
       colors: config.colors,
       random_colors: config.random_colors,
       target_colors: config.colors,
       lerp_time: config.color_interval,
       color_interval: config.color_interval,
       cycle_functions: config.cycle_functions,
       cycle_functions_interval: config.cycle_functions_interval,
       functions: functions
     }}
  end

  def handle_config(
        %{
          program: program,
          easing_interval: easing_interval,
          invert_colors: invert_colors,
          colors: colors,
          random_colors: random_colors,
          cycle_functions: cycle_functions
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
         colors: colors,
         random_colors: random_colors,
         cycle_functions: cycle_functions
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

  def handle_info(:update_colors, %State{random_colors: true} = state) do
    hue_a = :rand.uniform(360) - 1
    hue_b = Integer.mod(hue_a + 90 + :rand.uniform(180) - 1, 360)
    sat_a = 70 + :rand.uniform(29)
    sat_b = 70 + :rand.uniform(29)
    hsv_a = Chameleon.HSV.new(hue_a, sat_a, 100)
    hsv_b = Chameleon.HSV.new(hue_b, sat_b, 100)
    %Chameleon.RGB{r: r1, g: g1, b: b1} = Chameleon.convert(hsv_a, Chameleon.RGB)
    %Chameleon.RGB{r: r2, g: g2, b: b2} = Chameleon.convert(hsv_b, Chameleon.RGB)
    colors = {[r1, g1, b1], [r2, g2, b2]}

    {:noreply,
     %State{
       state
       | last_colors: state.colors,
         target_colors: colors,
         lerp_time: state.color_interval
     }}
  end

  def handle_info(:update_colors, state), do: {:noreply, state}

  def handle_info(:cycle_functions, %State{cycle_functions: true, functions: functions} = state) do
    [{source, function}] = Enum.take(functions, 1)
    functions = Stream.drop(functions, 1)

    Process.send_after(self(), :cycle_functions, trunc(state.cycle_functions_interval * 1000))
    {:noreply, %State{state | functions: functions, program: function, source: source}}
  end

  def handle_info(:cycle_functions, %State{} = state) do
    Process.send_after(self(), :cycle_functions, trunc(state.cycle_functions_interval * 1000))
    {:noreply, state}
  end

  def handle_info(:tick, %State{} = state) do
    state = lerp_toward_target_colors(state)

    canvas = state |> render()

    canvas
    |> Canvas.to_frame(drop: true)
    |> Map.put(:easing_interval, state.easing_interval)
    |> send_frame()

    {:noreply, %State{state | canvas: canvas}}
  end

  defp render(%State{canvas: canvas, program: program} = state) do
    {seconds, micros} = Time.utc_now() |> Time.to_seconds_after_midnight()
    seconds = seconds + micros / 1_000_000

    offset_x = :math.sin(0.3 + seconds * 0.17) * 2.0
    offset_y = :math.cos(0.7 + seconds * 0.05) * 2.0

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
      {{x, y}, pixels(program, x + offset_x, y + offset_y, i, seconds, colors)}
    end
  end

  @default_env %{'pi' => :math.pi(), 'tau' => :math.pi() * 2}

  defp pixels(expr, x, y, i, t, {color_a, color_b}) do
    env = [%{'x' => x, 'y' => y, 'i' => i, 't' => t}, @default_env]

    value =
      expr
      |> Program.eval(env)
      |> max(-1.0)
      |> min(1.0)

    interpolate_colors(color_a, color_b, value)
  end

  defp interpolate_colors([r1, g1, b1], [r2, g2, b2], value) do
    cond do
      value > 0 -> [r1 * value, g1 * value, b1 * value]
      value < 0 -> [r2 * -value, g2 * -value, b2 * -value]
      true -> [0, 0, 0]
    end
    |> Enum.map(&Kernel.trunc/1)
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

  defp lerp_rgb([r1, g1, b1], [r2, g2, b2], value) do
    hsl_a = Chameleon.RGB.new(r1, g1, b1) |> Chameleon.convert(Chameleon.HSL)
    hsl_b = Chameleon.RGB.new(r2, g2, b2) |> Chameleon.convert(Chameleon.HSL)
    h = lerp(hsl_a.h, hsl_b.h, value) |> trunc()
    s = lerp(hsl_a.s, hsl_b.s, value) |> trunc()
    l = lerp(hsl_a.l, hsl_b.l, value) |> trunc()

    %Chameleon.RGB{r: r, g: g, b: b} =
      Chameleon.HSL.new(h, s, l)
      |> Chameleon.convert(Chameleon.RGB)

    [r, g, b]
  end

  defp lerp(a, b, t) do
    (1 - t) * a + t * b
  end
end
