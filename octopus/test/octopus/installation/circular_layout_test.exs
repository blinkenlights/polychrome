defmodule Octopus.Installation.CircularLayoutTest do
  use ExUnit.Case, async: false

  alias Octopus.Installation
  alias Octopus.Installation.Nation2026

  setup do
    prev = Application.fetch_env!(:octopus, :installation)
    Application.put_env(:octopus, :installation, Nation2026)
    on_exit(fn -> Application.put_env(:octopus, :installation, prev) end)
    :ok
  end

  defp generic_layout do
    Installation.simulator_layouts() |> Enum.find(&(&1.background_image in [nil, ""]))
  end

  test "circularizes the generic layout for a circular installation" do
    layout = generic_layout()

    assert layout.name == "Generic Development View"
    assert length(layout.panel_centers) == Installation.num_panels()
    assert length(layout.panel_rotations) == Installation.num_panels()
    assert layout.panel_pixel_count == 64

    {panel_width, panel_height} = Installation.panel_layout()
    assert length(layout.positions) == Installation.num_panels() * panel_width * panel_height
  end

  test "image-backed layouts keep absolute positions (not rearranged into a ring)" do
    layout = Installation.simulator_layouts() |> Enum.find(&(&1.name == "Nation 2026"))

    assert layout.panel_centers == nil
    assert layout.panel_rotations == nil
    # Panel metadata (for the hover tooltip) is attached to every layout.
    assert layout.panel_pixel_count == 64
    assert length(layout.panel_info) == Installation.num_panels()
  end

  test "panel angles match Installation.panel_positions_m/1 (north at top, clockwise)" do
    layout = generic_layout()
    positions = Installation.panel_positions_m(reference: :inner_face)

    assert layout.panel_rotations == Enum.map(positions, & &1.theta_deg)

    north_index = Installation.north_panel() - 1
    assert Enum.at(layout.panel_rotations, north_index) == 0.0

    {north_x, north_y} = Enum.at(layout.panel_centers, north_index)
    {image_w, image_h} = layout.image_size
    # North sits at the top-center: horizontally centered, smallest y.
    assert_in_delta north_x, image_w / 2, 0.5
    assert north_y < image_h / 2
  end

  test "every panel's pixel matrix stays undistorted (square pixel cells, uniform per-panel size)" do
    layout = generic_layout()
    {pixel_w, pixel_h} = layout.pixel_size
    {panel_width, panel_height} = Installation.panel_layout()

    xs = layout.positions |> Enum.map(&elem(&1, 0))
    ys = layout.positions |> Enum.map(&elem(&1, 1))

    assert_in_delta Enum.max(xs) - Enum.min(xs), panel_width * pixel_w - pixel_w, 1.0e-6
    assert_in_delta Enum.max(ys) - Enum.min(ys), panel_height * pixel_h - pixel_h, 1.0e-6
  end

  test "panel centers stay within the reported image bounds" do
    layout = generic_layout()
    {image_w, image_h} = layout.image_size

    Enum.each(layout.panel_centers, fn {x, y} ->
      assert x >= 0.0 and x <= image_w
      assert y >= 0.0 and y <= image_h
    end)
  end

  test "leaves vertical padding above/below the ring so it doesn't touch the view edges" do
    layout = generic_layout()
    {_image_w, image_h} = layout.image_size
    {_panel_width, panel_height} = Installation.panel_layout()
    {_pixel_w, pixel_h} = layout.pixel_size
    panel_px_h = panel_height * pixel_h
    half_diag = :math.sqrt(2) * panel_px_h / 2

    ys = Enum.map(layout.panel_centers, &elem(&1, 1))
    min_y = Enum.min(ys) - half_diag
    max_y = Enum.max(ys) + half_diag

    assert min_y > 0.0
    assert max_y < image_h
  end

  test "panel_info carries panel number, controller, wiring and matrix size for every panel" do
    layout = generic_layout()
    {panel_width, panel_height} = Installation.panel_layout()

    assert length(layout.panel_info) == Installation.num_panels()

    Enum.zip(1..Installation.num_panels(), layout.panel_info)
    |> Enum.each(fn {n, info} ->
      assert info.panel == n
      assert info.width == panel_width
      assert info.height == panel_height
      assert is_binary(info.controller)
      assert is_binary(info.wiring)
    end)
  end
end
