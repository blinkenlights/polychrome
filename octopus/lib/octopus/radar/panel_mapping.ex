defmodule Octopus.Radar.PanelMapping do
  @moduledoc """
  Maps radar track positions (meters, installation frame) to LED panel indices.

  Geometry matches the A-Frame sim (`pixels3daframe.ts`) and Collective
  animations:

    * 3D panel `i` sits at world angle `i / N · 2π` (position `sin, cos · R`).
    * Canvas / frame panel index is `N - 1 - i` (see `textureIdx = numPanels - i - 1`).
    * Nearest panel uses `round(norm · N)`, not `trunc` — trunc skews by one
      panel near sector boundaries (the common “always one panel off” bug).

  Radar ground plane: `x` = left/right, `y` = front/back (A-Frame `z`).
  """

  @default_panel_width 8
  # aframe panelDiameter 18 m → 9 m ring radius
  @ring_radius_m 9.0

  @type track :: %{required(:x) => float(), required(:y) => float(), optional(atom()) => any()}

  def ring_radius, do: @ring_radius_m

  def track_radius(%{x: x, y: y}), do: :math.sqrt(x * x + y * y)

  def track_speed(%{vx: vx, vy: vy}), do: :math.sqrt(vx * vx + vy * vy)

  def track_speed(_), do: 0.0

  @doc """
  Normalised bearing 0..1 from installation center (`atan2(x, y)`).
  """
  def angle_norm(%{x: x, y: y}) do
    a = :math.atan2(x, y)
    :math.fmod(a + 2.0 * :math.pi(), 2.0 * :math.pi()) / (2.0 * :math.pi())
  end

  @doc """
  Nearest 3D panel index (0..N-1), same rule as Collective Tempest.
  """
  def sim_panel_3d(track, num_panels) do
    num_panels
    |> Kernel.*(angle_norm(track))
    |> round()
    |> rem(num_panels)
  end

  @doc """
  Canvas / frame panel index (0..N-1) for a 3D panel index.
  """
  def frame_panel_of_3d(sim_panel, num_panels), do: num_panels - 1 - sim_panel

  @doc """
  Returns `{frame_panel_index, x_within_panel, radius_m}`.
  `frame_panel_index` is 0-based (canvas column / installation slot).
  """
  def track_to_splash_pos(track, num_panels, panel_width \\ @default_panel_width) do
    {frame_panel, x} = track_to_panel_pos(track, num_panels, panel_width)
    {frame_panel, x, track_radius(track)}
  end

  @doc """
  Maps a track to `{frame_panel_index, x_within_panel}`.
  """
  def track_to_panel_pos(track, num_panels, panel_width \\ @default_panel_width) do
    norm = angle_norm(track)
    sim = sim_panel_3d(track, num_panels)
    frame_panel = frame_panel_of_3d(sim, num_panels)

    total = norm * num_panels * panel_width
    within = (total - sim * panel_width) |> trunc() |> clamp(0, panel_width - 1)

    {frame_panel, within}
  end

  def in_ring?(track, inner_m, outer_m) do
    r = track_radius(track)
    r >= inner_m and r <= outer_m
  end

  defp clamp(value, lo, hi), do: value |> max(lo) |> min(hi)
end
