defmodule Octopus.Apps.PixelFun.ProgramTest do
  use ExUnit.Case, async: true

  alias Octopus.Apps.PixelFun.Program

  test "parse/1 parses basic mathematical expressions" do
    assert {:ok, {:add, [1.0, {:mul, [2.0, 3.0]}]}} == Program.parse("1+2*3")
    assert {:ok, {:mul, [{:add, [1.0, 2.0]}, 3.0]}} == Program.parse("(1+2)*3")
    assert {:ok, {:pow, [{:unary_minus, [2.0]}, 10.0]}} == Program.parse("-2**10")
    assert {:ok, {:unary_minus, [{:pow, [2.0, 10.0]}]}} == Program.parse("-(2**10)")
  end

  test "parse/1 parses function calls" do
    assert {:ok, {:call, [~c"sin", 1.0]}} == Program.parse("sin(1)")
    assert {:ok, {:call, [~c"sin", {:call, [~c"cos", 1.0]}]}} == Program.parse("sin(cos(1))")
    assert {:ok, {:call, [~c"sinh", 1.0]}} == Program.parse("sinh(1)")
    assert {:ok, {:call, [~c"cosh", 0.0]}} == Program.parse("cosh(0)")
    assert {:ok, {:call, [~c"tanh", 1.0]}} == Program.parse("tanh(1)")
    assert {:ok, {:call, [~c"exp", 1.0]}} == Program.parse("exp(1)")
    assert {:ok, {:call, [~c"log", 2.718281828]}} == Program.parse("log(2.718281828)")
  end

  test "parse/1 parses identifiers" do
    assert {:ok, ~c"x"} == Program.parse("x")
    assert {:ok, ~c"_foo"} == Program.parse("_foo")
  end

  test "eval/2 evaluates basic mathematical expressions" do
    assert 7.0 == eval("1+2*3")
    assert 9.0 == eval("(1+2)*3")
    assert 1024.0 == eval("-2**10")
  end

  test "eval/2 evaluates boolean operators" do
    assert 1.0 == eval("1 || 0")
    assert 1.0 == eval("0 || 1")
    assert 0.1 == eval("0.1 || 1")
    assert 0.0 == eval("1 && 0")
    assert 0.1 == eval("1 && 0.1")
    assert 0.2 == eval("0.1 && 0.2")
  end

  test "eval/2 evaluates bitwise operators" do
    assert 0.0 == eval("0 | 0")
    assert 1.0 == eval("0 | 1")
    assert 1.0 == eval("0 | 1.1")
    assert 1.0 == eval("1 | 0")
    assert 1.0 == eval("1 | 1")
    assert 0.0 == eval("0 & 0")
    assert 0.0 == eval("0 & 1")
    assert 0.0 == eval("1 & 0")
    assert 1.0 == eval("1 & 1")
    assert 0.0 == eval("0 ^ 0")
    assert 1.0 == eval("0 ^ 1")
    assert 1.0 == eval("1 ^ 0")
    assert 0.0 == eval("1 ^ 1")
  end

  test "eval/2 evaluates bitwise shifts" do
    assert 0.0 == eval("0 << 1")
    assert 2.0 == eval("1 << 1")
    assert 4.0 == eval("1 << 2")
    assert 4.0 == eval("1.9 << 2")
    assert 0.0 == eval("0 >> 1")
    assert 0.0 == eval("1 >> 1")
    assert 2.0 == eval("4 >> 1")
    assert 1.0 == eval("4 >> 2")
  end

  test "eval/2 evaluates comparison operators" do
    assert 1.0 == eval("1 < 2")
    assert 0.0 == eval("1 < 1")
    assert 0.0 == eval("2 < 1")
    assert 1.0 == eval("1 <= 2")
    assert 1.0 == eval("1 <= 1")
    assert 0.0 == eval("2 <= 1")
    assert 0.0 == eval("1 > 2")
    assert 0.0 == eval("1 > 1")
    assert 1.0 == eval("2 > 1")
    assert 0.0 == eval("1 >= 2")
    assert 1.0 == eval("1 >= 1")
    assert 1.0 == eval("2 >= 1")
    assert 1.0 == eval("1 == 1")
    assert 0.0 == eval("1 == 2")
    assert 1.0 == eval("1 != 2")
    assert 0.0 == eval("1 != 1")
  end

  test "eval/2 evaluates function calls" do
    assert 1.0 == eval("sin(#{0.5 * :math.pi()})")
    assert 1.0 == eval("cos(#{2.0 * :math.pi()})")
    assert 1.557407724654902 == eval("tan(1)")
    assert 0.0 == eval("sinh(0)")
    assert 0.0 == eval("cosh(0)") - 1.0
    assert 0.0 == eval("tanh(0)")
    assert :math.tanh(1) == eval("tanh(1)")
    assert 1.0 == eval("exp(0)")
    assert 0.0 == eval("log(1)")
    assert :math.exp(1) == eval("exp(1)")
  end

  test "eval/2 evaluates PI alias via env" do
    env = [%{}, %{~c"PI" => :math.pi()}]
    assert_in_delta 0.0, eval("sin(PI)", env), 0.001
    assert :math.pi() == eval("PI", env)
  end

  test "eval/2 evaluates identifiers" do
    assert 1337.0 == eval("x", [%{~c"x" => 1337.0}])
    assert 1337.0 == eval("x+1", [%{~c"x" => 1336.0}])
  end

  defp eval(program, env \\ []) do
    {:ok, program} = Program.parse(program)
    Program.eval(program, env)
  end
end
