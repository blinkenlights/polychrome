defmodule Octopus.Apps.PixelFun.Program do
  require Logger

  import Bitwise

  def parse(program) when is_binary(program), do: program |> to_charlist() |> parse()

  def parse(program) when is_list(program) do
    with {:ok, tokens, _} <- :program_lexer.string(program ++ [0]),
         {:ok, ast} <- :program_parser.parse(tokens) do
      {:ok, ast}
    end
  end

  def eval(expr, env) do
    do_eval(expr, env)
  rescue
    ArithmeticError ->
      0.0
  end

  def do_eval(number, _env) when is_number(number), do: number
  def do_eval(ident, env) when is_list(ident), do: env_lookup(env, ident)

  def do_eval({:unary_plus, [expr]}, env), do: do_eval(expr, env)
  def do_eval({:unary_minus, [expr]}, env), do: -do_eval(expr, env)

  def do_eval({:add, [lhs, rhs]}, env), do: do_eval(lhs, env) + do_eval(rhs, env)
  def do_eval({:sub, [lhs, rhs]}, env), do: do_eval(lhs, env) - do_eval(rhs, env)
  def do_eval({:mul, [lhs, rhs]}, env), do: do_eval(lhs, env) * do_eval(rhs, env)
  def do_eval({:divi, [lhs, rhs]}, env), do: do_eval(lhs, env) / do_eval(rhs, env)
  def do_eval({:mod, [lhs, rhs]}, env), do: :math.fmod(do_eval(lhs, env), do_eval(rhs, env))

  def do_eval({:bitwise_or, [lhs, rhs]}, env) do
    bor(trunc(do_eval(lhs, env)), trunc(do_eval(rhs, env))) + 0.0
  end

  def do_eval({:bitwise_and, [lhs, rhs]}, env) do
    band(trunc(do_eval(lhs, env)), trunc(do_eval(rhs, env))) + 0.0
  end

  def do_eval({:bitwise_xor, [lhs, rhs]}, env) do
    bxor(trunc(do_eval(lhs, env)), trunc(do_eval(rhs, env))) + 0.0
  end

  def do_eval({:shift_left, [lhs, rhs]}, env) do
    bsl(trunc(do_eval(lhs, env)), trunc(do_eval(rhs, env))) + 0.0
  end

  def do_eval({:shift_right, [lhs, rhs]}, env) do
    bsr(trunc(do_eval(lhs, env)), trunc(do_eval(rhs, env))) + 0.0
  end

  def do_eval({:logical_or, [lhs, rhs]}, env) do
    case {do_eval(lhs, env), do_eval(rhs, env)} do
      {0.0, rhs} -> rhs
      {lhs, _rhs} -> lhs
    end
  end

  def do_eval({:lt, [lhs, rhs]}, env) do
    if do_eval(lhs, env) < do_eval(rhs, env), do: 1.0, else: 0.0
  end

  def do_eval({:gt, [lhs, rhs]}, env) do
    if do_eval(lhs, env) > do_eval(rhs, env), do: 1.0, else: 0.0
  end

  def do_eval({:lte, [lhs, rhs]}, env) do
    if do_eval(lhs, env) <= do_eval(rhs, env), do: 1.0, else: 0.0
  end

  def do_eval({:gte, [lhs, rhs]}, env) do
    if do_eval(lhs, env) >= do_eval(rhs, env), do: 1.0, else: 0.0
  end

  def do_eval({:eq, [lhs, rhs]}, env) do
    if do_eval(lhs, env) == do_eval(rhs, env), do: 1.0, else: 0.0
  end

  def do_eval({:neq, [lhs, rhs]}, env) do
    if do_eval(lhs, env) != do_eval(rhs, env), do: 1.0, else: 0.0
  end

  def do_eval({:logical_and, [lhs, rhs]}, env) do
    case {do_eval(lhs, env), do_eval(rhs, env)} do
      {0.0, _rhs} -> 0.0
      {_lhs, rhs} -> rhs
    end
  end

  def do_eval({:pow, [lhs, rhs]}, env), do: :math.pow(do_eval(lhs, env), do_eval(rhs, env))

  def do_eval({:call, ['rand']}, _env), do: :rand.uniform()
  def do_eval({:call, ['random']}, _env), do: :rand.uniform()

  def do_eval({:call, ['abs', expr]}, env), do: expr |> do_eval(env) |> abs()
  def do_eval({:call, ['sqrt', expr]}, env), do: expr |> do_eval(env) |> :math.sqrt()

  def do_eval({:call, ['hypot', a, b]}, env),
    do: :math.sqrt(do_eval(a, env) ** 2 + do_eval(b, env) ** 2)

  def do_eval({:call, ['sin', expr]}, env), do: expr |> do_eval(env) |> :math.sin()
  def do_eval({:call, ['cos', expr]}, env), do: expr |> do_eval(env) |> :math.cos()
  def do_eval({:call, ['tan', expr]}, env), do: expr |> do_eval(env) |> :math.tan()

  def do_eval({:call, ['asin', expr]}, env), do: expr |> do_eval(env) |> :math.asin()
  def do_eval({:call, ['acos', expr]}, env), do: expr |> do_eval(env) |> :math.acos()
  def do_eval({:call, ['atan', expr]}, env), do: expr |> do_eval(env) |> :math.atan()
  def do_eval({:call, ['atan2', a, b]}, env), do: :math.atan2(do_eval(env, a), do_eval(env, b))

  def do_eval({:call, ['asinh', expr]}, env), do: expr |> do_eval(env) |> :math.asinh()
  def do_eval({:call, ['acosh', expr]}, env), do: expr |> do_eval(env) |> :math.acosh()
  def do_eval({:call, ['atanh', expr]}, env), do: expr |> do_eval(env) |> :math.atanh()

  def do_eval({:call, ['floor', expr]}, env), do: expr |> do_eval(env) |> Float.floor()
  def do_eval({:call, ['ceil', expr]}, env), do: expr |> do_eval(env) |> Float.ceil()
  def do_eval({:call, ['round', expr]}, env), do: expr |> do_eval(env) |> Float.round()

  def do_eval({:call, ['fract', expr]}, env) do
    value = do_eval(expr, env)
    value - trunc(value)
  end

  def do_eval(_expr, _env), do: 0.0

  defp env_lookup([], _ident), do: 0.0

  defp env_lookup([env | rest], ident) do
    case Map.get(env, ident) do
      nil -> env_lookup(rest, ident)
      value -> value
    end
  end
end
