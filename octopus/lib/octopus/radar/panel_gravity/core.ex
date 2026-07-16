defmodule Octopus.Radar.PanelGravity.Core do
  @moduledoc false

  alias Octopus.Radar.PanelGravity.Settings

  @type person :: %{
          required(:id) => pos_integer(),
          required(:x) => float(),
          required(:y) => float(),
          optional(:vx) => float(),
          optional(:vy) => float()
        }

  @type panel_map :: %{pos_integer() => float()}

  @type panel_pos :: %{
          required(:panel) => pos_integer(),
          required(:x) => float(),
          required(:y) => float()
        }

  @doc """
  Computes a linear nearest-object gravity value (0..1) for every panel.

  Strategy:
  - All panels always emit at least `floor` (floor_pct / 100).
  - Only the closest object within `far_dist_m` of each panel is considered.
  - At distance ≤ `near_dist_m` the panel reaches `max_g` (max_gravity_pct / 100).
  - At distance == `far_dist_m` the panel is back at `floor`.
  - Linear interpolation between the two distance endpoints.

  `far_dist_m` is typically `ring_radius_m - platform_radius_m` so only people
  who have left the central platform contribute above the floor.
  """
  @spec raw_gravity([person()], [panel_pos()], float(), float(), float(), float()) :: panel_map()
  def raw_gravity(people, panel_positions, near_dist_m, far_dist_m, floor, max_g) do
    falloff_range = max(far_dist_m - near_dist_m, 0.01)
    base = empty_panels(panel_positions)

    Enum.reduce(panel_positions, base, fn panel_pos, acc ->
      g = nearest_gravity(people, panel_pos, far_dist_m, near_dist_m, falloff_range, floor, max_g)
      Map.put(acc, panel_pos.panel, g)
    end)
  end

  @doc """
  Symmetric per-panel first-order lag (EMA) toward target.

  Uses a single `easing_tau` for both rising and falling so appearance and
  disappearance of objects build and fade at the same rate.
  """
  @spec smooth(panel_map(), panel_map(), float(), Settings.t()) :: panel_map()
  def smooth(level, target, dt, %Settings{easing_tau: tau}) do
    alpha = 1.0 - :math.exp(-dt / max(tau, 0.01))

    Map.merge(level, target, fn _panel, cur, tgt ->
      cur + (tgt - cur) * alpha
    end)
  end

  @doc """
  Empty installation-panel map (1..N) with zero values.
  """
  @spec empty_installation_panels(pos_integer()) :: panel_map()
  def empty_installation_panels(num_panels) do
    for p <- 1..num_panels, into: %{}, do: {p, 0.0}
  end

  @spec empty_panels([panel_pos()]) :: panel_map()
  def empty_panels(panel_positions) do
    Map.new(panel_positions, fn %{panel: panel} -> {panel, 0.0} end)
  end

  # Returns gravity (0..1) based on the nearest qualifying object.
  # When no object is in range the panel holds the floor value.
  defp nearest_gravity([], _panel_pos, _far, _near, _range, floor, _max_g), do: floor

  defp nearest_gravity(people, %{x: px, y: py}, far_dist_m, near_dist_m, falloff_range, floor, max_g) do
    nearest =
      Enum.reduce(people, :none, fn %{x: x, y: y}, best ->
        d = :math.sqrt((x - px) * (x - px) + (y - py) * (y - py))

        if d <= far_dist_m do
          case best do
            :none -> d
            prev -> min(prev, d)
          end
        else
          best
        end
      end)

    case nearest do
      :none ->
        floor

      d ->
        # Linear from max_g at near_dist_m down to floor at far_dist_m.
        t = 1.0 - max(0.0, d - near_dist_m) / falloff_range
        floor + (max_g - floor) * clamp01(t)
    end
  end

  defp clamp01(v), do: v |> max(0.0) |> min(1.0)
end
