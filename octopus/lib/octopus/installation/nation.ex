defmodule Octopus.Installation.Nation do
  @behaviour Octopus.Installation

  @panel_height 8
  @panel_width 8
  @panels_offsets [
    {0, 0},
    {25 * 1, 0},
    {25 * 2, 0},
    {25 * 3, 0},
    {25 * 4, 0},
    {25 * 5, 0},
    {25 * 6, 0},
    {25 * 7, 0},
    {25 * 8, 0},
    {25 * 9, 0}
  ]

  @impl true
  def panel_offsets() do
    @panels_offsets
  end

  @impl true
  def panel_width() do
    @panel_width
  end

  @impl true
  def panel_height() do
    @panel_height
  end

  @impl true
  def center_x() do
    width() / 2 - 0.5
  end

  @impl true
  def center_y() do
    height() / 2 - 0.5
  end

  @impl true
  def width() do
    {min_x, max_x} = panels() |> List.flatten() |> Enum.map(fn {x, _y} -> x end) |> Enum.min_max()
    max_x - min_x + 1
  end

  @impl true
  def height() do
    {min_y, max_y} = panels() |> List.flatten() |> Enum.map(fn {_x, y} -> y end) |> Enum.min_max()
    max_y - min_y + 1
  end

  @impl true
  def panels() do
    for {offset_x, offset_y} <- @panels_offsets do
      for y <- 0..(@panel_height - 1), x <- 0..(@panel_width - 1) do
        {
          x + offset_x,
          y + offset_y
        }
      end
    end
  end

  @impl true
  def simulator_layouts() do
    positions = panels() |> List.flatten()
    {min_x, max_x} = positions |> Enum.map(fn {x, _y} -> x end) |> Enum.min_max()
    {min_y, max_y} = positions |> Enum.map(fn {_x, y} -> y end) |> Enum.min_max()

    [
      %Octopus.Layout{
        name: "Nation",
        positions: positions,
        width: max_x - min_x + 1,
        height: max_y - min_y + 1,
        pixel_size: {4, 4},
        pixel_margin: {0, 0, 0, 0},
        background_image: "/images/nation.webp",
        pixel_image: "/images/mildenberg-pixel-overlay.webp",
        image_size: {6458, Atom}
      }
    ]
  end
end
