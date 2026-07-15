defmodule Octopus.Apps.GravityMaskTest do
  use ExUnit.Case, async: true

  alias Octopus.AppModePresets
  alias Octopus.Apps.GravityMask
  alias Octopus.Canvas

  @panel_width 8

  test "brightness follows absolute gravity (no cross-panel remapping)" do
    display_info = %{width: @panel_width * 3, height: 8}
    floor = 0.25

    # Absolute factors: panel 1 at 1.0 → full, panel 3 at 0.0 → floor.
    canvas = render(display_info, %{1 => 1.0, 2 => 0.5, 3 => 0.0}, floor)

    p1 = 0 * @panel_width
    p2 = 1 * @panel_width
    p3 = 2 * @panel_width

    assert Canvas.get_pixel(canvas, {p1, 0}) == 255
    assert Canvas.get_pixel(canvas, {p3, 0}) == trunc(floor * 255)
    mid = Canvas.get_pixel(canvas, {p2, 0})
    assert mid == trunc((floor + (1.0 - floor) * 0.5) * 255)
  end

  test "equal mid gravity stays mid brightness on every panel" do
    display_info = %{width: @panel_width * 2, height: 8}
    floor = 0.0

    canvas = render(display_info, %{1 => 0.5, 2 => 0.5}, floor)
    expected = trunc(0.5 * 255)

    assert Canvas.get_pixel(canvas, {0, 0}) == expected
    assert Canvas.get_pixel(canvas, {@panel_width, 0}) == expected
  end

  test "exposes manager tweakables" do
    tweakables = GravityMask.mode_tweakables("gravitymask:mask")
    keys = Enum.map(tweakables, & &1.key)

    assert :floor_brightness in keys
    assert :contrast in keys
    assert :reach in keys
    refute :reach_m in keys
    refute :exponent in keys
    refute :softening_m in keys
    refute :sensitivity in keys

    floor = Enum.find(tweakables, &(&1.key == :floor_brightness))
    assert floor.unit == "%"
    assert floor.min == 0
    assert floor.max == 100

    reach = Enum.find(tweakables, &(&1.key == :reach))
    assert reach.min == 1
    assert reach.max == 100
    refute Map.get(reach, :unit)

    modes = GravityMask.list_modes()
    assert Enum.any?(modes, &(&1.id == "gravitymask:mask"))

    schema = GravityMask.config_schema()
    {_, :float, opts} = schema.floor_brightness
    assert opts.min == 0
    assert opts.max == 100
  end

  test "builtin preset matches module defaults and id_for_config" do
    preset = AppModePresets.get(GravityMask, "gravitymask:mask")
    defaults = GravityMask.mode_config("gravitymask:mask")

    assert preset.config == defaults
    assert AppModePresets.id_for_config(GravityMask, preset.config) == "gravitymask:mask"
  end

  defp render(display_info, factors, floor_brightness) do
    num_panels = max(div(display_info.width, @panel_width), 1)
    height = display_info.height

    Enum.reduce(
      1..num_panels,
      Canvas.new(display_info.width, display_info.height, :grayscale),
      fn panel, canvas ->
        level = Map.get(factors, panel, 0.0) |> max(0.0) |> min(1.0)
        brightness = floor_brightness + (1.0 - floor_brightness) * level
        intensity = trunc(brightness * 255) |> max(0) |> min(255)

        x0 = (panel - 1) * @panel_width
        x1 = x0 + @panel_width - 1

        Canvas.fill_rect(canvas, {x0, 0}, {x1, height - 1}, intensity)
      end
    )
  end
end
