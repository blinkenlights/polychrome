defmodule Octopus.Installation.CircularLayout do
  @moduledoc """
  Rearranges a "generic" (no background image) pixel simulator layout into a
  ring, for `:circular` installations. Panel angles are taken from
  `Octopus.Installation.panel_positions_m/1` — the same source
  `OctopusWeb.RadarLive`'s ring view uses — so panel order/orientation match
  across the radar map and the pixel simulator.

  Each panel keeps its own 8x8-ish pixel matrix perfectly square; panels are
  placed and rotated as rigid bodies around the ring, never sheared into a
  trapezoid. At its computed position, a panel's bottom matrix row faces the
  ring center and its top row faces outward.

  The ring radius is derived from panel/pixel sizes (not real-world meters):
  it's picked so the ring's circumference roughly matches the panels' total
  linear width (same panels + gaps as the non-circular generic layout), which
  keeps proportions sane regardless of installation scale.
  """

  alias Octopus.Installation
  alias Octopus.Layout

  # Extra breathing room above/below the ring (as a fraction of one panel's
  # pixel height) so the circle doesn't touch the view chrome (toolbar,
  # button panel, ...) above/below it. The ring already has natural padding
  # on the left/right from its own curvature, so only top/bottom needs it.
  @vertical_padding_ratio 1.5

  @spec build(Layout.t()) :: Layout.t()
  def build(%Layout{pixel_size: {pixel_width, pixel_height}} = layout) do
    num_panels = Installation.num_panels()
    {panel_width, panel_height} = Installation.panel_layout()

    panel_px_w = panel_width * pixel_width
    panel_px_h = panel_height * pixel_height
    gap_px = Installation.panel_gap() * pixel_width

    ring_radius_px = num_panels * (panel_px_w + gap_px) / (2 * :math.pi())
    matrix_center_radius_px = ring_radius_px + panel_px_h / 2

    thetas_deg =
      Installation.panel_positions_m(reference: :inner_face)
      |> Enum.map(& &1.theta_deg)

    raw_panel_centers =
      Enum.map(thetas_deg, &panel_center(&1, matrix_center_radius_px))

    {panel_centers, {width_px, height_px}} =
      shift_into_bounds(raw_panel_centers, panel_px_w, panel_px_h, panel_px_h * @vertical_padding_ratio)

    local_positions = local_pixel_positions(panel_width, panel_height, pixel_width, pixel_height)
    positions = Enum.flat_map(1..num_panels, fn _ -> local_positions end)

    %Layout{
      layout
      | positions: positions,
        width: num_panels * panel_width,
        height: panel_height,
        image_size: {ceil(width_px), ceil(height_px)},
        panel_centers: panel_centers,
        panel_rotations: thetas_deg,
        panel_pixel_count: panel_width * panel_height
    }
  end

  # World-plane bearing `theta_deg` (clockwise from north) → the panel matrix
  # center's raw (unshifted) canvas position, at the given radius. Matches
  # `Installation.panel_positions_m/1`'s `x = r*sin(theta), y = r*cos(theta)`,
  # with y flipped so +north renders "up" on canvas.
  defp panel_center(theta_deg, radius_px) do
    theta_rad = theta_deg * :math.pi() / 180.0
    {radius_px * :math.sin(theta_rad), -radius_px * :math.cos(theta_rad)}
  end

  # Pixel centers relative to their panel's own center (pre-rotation), in
  # frame-data order (row-major, matching `Installation.generate_generic_layout/6`).
  defp local_pixel_positions(panel_width, panel_height, pixel_width, pixel_height) do
    panel_px_w = panel_width * pixel_width
    panel_px_h = panel_height * pixel_height

    for y <- 0..(panel_height - 1), x <- 0..(panel_width - 1) do
      {
        (x + 0.5) * pixel_width - panel_px_w / 2,
        (y + 0.5) * pixel_height - panel_px_h / 2
      }
    end
  end

  # Shifts every panel center so the smallest resulting canvas coordinate is
  # `0`, and returns the bounding image size that fits every panel's full
  # (rotation-agnostic) footprint, plus `vertical_padding_px` of extra
  # whitespace split evenly above and below the ring.
  defp shift_into_bounds(panel_centers, panel_px_w, panel_px_h, vertical_padding_px) do
    half_diag = :math.sqrt(panel_px_w * panel_px_w + panel_px_h * panel_px_h) / 2
    half_v_pad = vertical_padding_px / 2

    xs = Enum.map(panel_centers, &elem(&1, 0))
    ys = Enum.map(panel_centers, &elem(&1, 1))
    min_x = Enum.min(xs) - half_diag
    min_y = Enum.min(ys) - half_diag - half_v_pad
    max_x = Enum.max(xs) + half_diag
    max_y = Enum.max(ys) + half_diag + half_v_pad

    shifted = Enum.map(panel_centers, fn {x, y} -> {x - min_x, y - min_y} end)

    {shifted, {max_x - min_x, max_y - min_y}}
  end
end
