defmodule Octopus.SwayTest do
  use ExUnit.Case, async: true

  alias Octopus.Apps.PixelFun
  alias Octopus.Installation
  alias Octopus.Sway

  setup do
    original_installation = Application.get_env(:octopus, :installation)

    on_exit(fn ->
      Application.put_env(:octopus, :installation, original_installation)
    end)

    Application.put_env(:octopus, :installation, Octopus.Installation.Nation2026)
    :ok
  end

  test "wobble mode uses constant amplitude and advancing phase" do
    assert Sway.params(2.0, 0.5, :wobble, 3.0) == {2.0, 1.5}
  end

  test "pendulum mode oscillates amplitude with zero phase" do
    {amp, phase} = Sway.params(2.0, 1.0, :pendulum, :math.pi() / 2)
    assert_in_delta amp, 2.0, 0.0001
    assert phase == 0.0
  end

  test "offset is W-periodic in x" do
    w = 100.0
    amplitude = 1.5
    phase = 0.7

    assert_in_delta Sway.offset(12.3, w, amplitude, phase),
                    Sway.offset(12.3 + w, w, amplitude, phase),
                    0.0001
  end

  test "quarter-period offsets differ by roughly full amplitude swing" do
    w = 100.0
    amplitude = 2.0
    phase = 0.0

    o0 = Sway.offset(0, w, amplitude, phase)
    o_quarter = Sway.offset(w / 4, w, amplitude, phase)

    assert_in_delta o_quarter - o0, amplitude, 0.05
  end

  test "matches PixelFun transform tilt component on Nation2026 within small-angle tolerance" do
    w = Installation.width()

    params = %{
      seconds: 1.7,
      tilt_scale: 1.0,
      tilt_speed: 0.5,
      tilt_mode: :wobble
    }

    x = 42
    y = 3

    {_x_out, y_pixel_fun} = PixelFun.transform_pixel_coords(x, y, params)

    {amplitude, phase} = Sway.params(1.0, 0.5, :wobble, 1.7)
    center_y = Installation.height() / 2 - 0.5
    y_scaled = y - center_y
    y_expected = y_scaled + Sway.offset(x, w, amplitude, phase)

    assert_in_delta y_pixel_fun, y_expected, 0.02
  end
end
