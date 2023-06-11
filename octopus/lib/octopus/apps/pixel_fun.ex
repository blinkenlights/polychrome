defmodule Octopus.Apps.PixelFun do
  use Octopus.App

  alias Octopus.Canvas

  defmodule Parser do
    import NimbleParsec

    ident_first = ascii_string([?A..?Z, ?a..?z, ?_], min: 1)
    ident_rest = ascii_string([?A..?Z, ?a..?z, ?0..?9, ?_], min: 1)
    ident = ident_first |> repeat(ident_rest) |> reduce({Enum, :join, []})

    float =
      ascii_string([?0..?9], min: 1)
      |> concat(
        optional(
          string(".")
          |> ascii_string([?0..?9], min: 1)
        )
      )
      |> reduce({Enum, :join, [""]})
      |> map({Float, :parse, []})
      |> map({Kernel, :elem, [0]})
      |> label("number")

    atom = empty() |> choice([ident, float], gen_weights: [1, 2]) |> label("atom")

    call =
      choice([
        ident
        |> ignore(ascii_char([?(]))
        |> parsec(:expr)
        |> ignore(ascii_char([?)]))
        |> tag(:call),
        atom
      ])

    factor =
      empty()
      |> choice(
        [
          ignore(ascii_char([?(]))
          |> concat(parsec(:expr))
          |> ignore(ascii_char([?)])),
          call
        ],
        gen_weights: [1, 3]
      )

    defcombinatorp(
      :term,
      empty()
      |> choice(
        [
          factor
          |> ignore(ascii_char([?*]))
          |> ignore(ascii_char([?*]))
          |> concat(parsec(:term))
          |> tag(:pow),
          factor
          |> ignore(ascii_char([?*]))
          |> concat(parsec(:term))
          |> tag(:mul),
          factor
          |> ignore(ascii_char([?\%]))
          |> concat(parsec(:term))
          |> tag(:mod),
          factor
          |> ignore(ascii_char([?/]))
          |> concat(parsec(:term))
          |> tag(:div),
          factor
        ],
        gen_weights: [1, 2, 2, 2, 3]
      ),
      export_metadata: true
    )

    defcombinatorp(
      :expr,
      empty()
      |> choice(
        [
          parsec(:term)
          |> ignore(ascii_char([?+]))
          |> concat(parsec(:expr))
          |> tag(:plus),
          parsec(:term)
          |> ignore(ascii_char([?-]))
          |> concat(parsec(:expr))
          |> tag(:minus),
          parsec(:term)
        ],
        gen_weights: [1, 1, 3]
      ),
      export_metadata: true
    )

    defparsec(:parse, parsec(:expr), export_metadata: true)
  end

  def name(), do: "Pixel Fun"

  @width 8 * 10 + 9 * 18
  @height 8

  def init(_args) do
    :timer.send_interval((1000 / 60) |> trunc(), :tick)

    canvas = Canvas.new(@width, @height)

    {:ok, [program], "", %{}, _, _} = "sin(t-sqrt((x-3.5)**2+(y-3.5)**2))" |> Parser.parse()

    {:ok, %{canvas: canvas, program: program}}
  end

  def update_program(pid, program) do
    GenServer.cast(pid, {:update_program, program})
  end

  def handle_cast({:update_program, program}, state) do
    program =
      case Parser.parse(program) do
        {:ok, [program], "", %{}, _, _} -> program
        _ -> 0
      end

    {:noreply, %{state | program: program}}
  end

  def handle_info(:tick, state) do
    canvas = state |> render()
    canvas |> Canvas.to_frame(drop: true) |> send_frame()

    {:noreply, %{state | canvas: canvas}}
  end

  def render(%{canvas: canvas, program: program} = _state) do
    {seconds, micros} = Time.utc_now() |> Time.to_seconds_after_midnight()
    seconds = seconds + micros / 1_000_000

    for i <- 0..(@width * @height - 1), into: canvas do
      x = rem(i, @width)
      y = div(i, @width)
      {{x, y}, pixels(program, x, y, i, seconds)}
    end
  end

  def sin(x), do: :math.sin(x)
  def cos(x), do: :math.cos(x)
  def tan(x), do: :math.tan(x)

  def pixels(expr, x, y, i, t) do
    env = [%{"x" => x, "y" => y, "i" => i, "t" => t}]

    value =
      expr
      |> eval(env)
      |> max(-1.0)
      |> min(1.0)

    rgb =
      cond do
        value > 0 -> [0x3F * value, 0xFF * value, 0x21 * value]
        value < 0 -> [0xFB * -value, 0x48 * -value, 0xC4 * -value]
        true -> [0, 0, 0]
      end
      |> Enum.map(&Kernel.trunc/1)

    rgb
  end

  defp eval(number, _env) when is_number(number), do: number
  defp eval(ident, env) when is_binary(ident), do: env_lookup(env, ident)

  defp eval({:plus, [lhs, rhs]}, env), do: eval(lhs, env) + eval(rhs, env)
  defp eval({:minus, [lhs, rhs]}, env), do: eval(lhs, env) - eval(rhs, env)
  defp eval({:mul, [lhs, rhs]}, env), do: eval(lhs, env) * eval(rhs, env)
  defp eval({:div, [lhs, rhs]}, env), do: eval(lhs, env) / eval(rhs, env)
  defp eval({:mod, [lhs, rhs]}, env), do: fmod(eval(lhs, env), eval(rhs, env))

  defp eval({:pow, [lhs, rhs]}, env), do: :math.pow(eval(lhs, env), eval(rhs, env))

  defp eval({:call, ["abs", expr]}, env), do: expr |> eval(env) |> abs()
  defp eval({:call, ["random"]}, _env), do: :rand.uniform()

  defp eval({:call, ["sqrt", expr]}, env) do
    expr
    |> eval(env)
    |> :math.sqrt()
  end

  defp eval({:call, ["hypot", a, b]}, env), do: :math.sqrt(eval(env, a) ** 2 + eval(env, b) ** 2)

  defp eval({:call, ["sin", expr]}, env), do: expr |> eval(env) |> :math.sin()
  defp eval({:call, ["cos", expr]}, env), do: expr |> eval(env) |> :math.cos()
  defp eval({:call, ["tan", expr]}, env), do: expr |> eval(env) |> :math.tan()

  defp eval({:call, ["asin", expr]}, env), do: expr |> eval(env) |> :math.asin()
  defp eval({:call, ["acos", expr]}, env), do: expr |> eval(env) |> :math.acos()
  defp eval({:call, ["atan", expr]}, env), do: expr |> eval(env) |> :math.atan()
  defp eval({:call, ["atan2", a, b]}, env), do: :math.atan2(eval(env, a), eval(env, b))

  defp eval({:call, ["asinh", expr]}, env), do: expr |> eval(env) |> :math.asinh()
  defp eval({:call, ["acosh", expr]}, env), do: expr |> eval(env) |> :math.acosh()
  defp eval({:call, ["atanh", expr]}, env), do: expr |> eval(env) |> :math.atanh()

  defp eval({:call, ["floor", expr]}, env), do: expr |> eval(env) |> Float.floor()
  defp eval({:call, ["ceil", expr]}, env), do: expr |> eval(env) |> Float.ceil()
  defp eval({:call, ["round", expr]}, env), do: expr |> eval(env) |> Float.round()

  defp eval({:call, ["fract", expr]}, env) do
    value = eval(expr, env)
    value - trunc(value)
  end

  defp env_lookup([], _ident), do: 0

  defp env_lookup([env | rest], ident) do
    case Map.get(env, ident) do
      nil -> env_lookup(rest, ident)
      value -> value
    end
  end

  defp fmod(dividend, divisor) do
    quotient = floor(dividend / divisor)
    dividend - quotient * divisor
  end
end
