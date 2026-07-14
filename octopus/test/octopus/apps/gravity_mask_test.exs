defmodule Octopus.Apps.GravityMaskTest do
  use ExUnit.Case, async: true

  alias Octopus.Apps.GravityMask
  alias Octopus.Canvas
  alias Octopus.Radar.PanelMapping

  @panel_width 8

  test "brightness respects floor and scales with gravity factor" do
    display_info = %{width: @panel_width * 2, height: 8}
    floor = 0.25
    north_panel = 1

    low_canvas =
      render(display_info, %{1 => 0.0, 2 => 0.0}, floor, north_panel)

    high_canvas =
      render(display_info, %{1 => 1.0, 2 => 0.0}, floor, north_panel)

    panel1_x = PanelMapping.frame_panel_for_installation(1, 2, north_panel) * @panel_width
    panel2_x = PanelMapping.frame_panel_for_installation(2, 2, north_panel) * @panel_width

    low_intensity = Canvas.get_pixel(low_canvas, {panel1_x, 0})
    high_intensity = Canvas.get_pixel(high_canvas, {panel1_x, 0})
    far_intensity = Canvas.get_pixel(high_canvas, {panel2_x, 0})

    assert low_intensity == trunc(floor * 255)
    assert high_intensity == 255
    assert far_intensity == trunc(floor * 255)
    assert high_intensity > far_intensity
  end

  test "floor brightness cannot go below 25%" do
    assert GravityMask.__info__(:functions) |> Keyword.has_key?(:config_schema)

    schema = GravityMask.config_schema()
    {_, :float, opts} = schema.floor_brightness
    assert opts.min == 0.25
  end

  defp render(display_info, factors, floor_brightness, north_panel) do
    num_panels = max(div(display_info.width, @panel_width), 1)
    height = display_info.height

    Enum.reduce(
      1..num_panels,
      Canvas.new(display_info.width, display_info.height, :grayscale),
      fn panel, canvas ->
        level = Map.get(factors, panel, 0.0) |> clamp01()
        brightness = floor_brightness + (1.0 - floor_brightness) * level
        intensity = trunc(brightness * 255) |> max(0) |> min(255)

        frame_panel =
          PanelMapping.frame_panel_for_installation(panel, num_panels, north_panel)

        x0 = frame_panel * @panel_width
        x1 = x0 + @panel_width - 1

        Canvas.fill_rect(canvas, {x0, 0}, {x1, height - 1}, intensity)
      end
    )
  end

  defp clamp01(v), do: v |> max(0.0) |> min(1.0)
end
