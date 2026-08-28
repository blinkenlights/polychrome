defmodule Octopus.Apps.PixelFun.Transform.Sphere do
  @moduledoc """
  Circular-installation transform via unit-sphere orientation + Zoom/Merlin residual.

  Used when `Installation.arrangement() == :circular`.
  """

  alias Octopus.Apps.PixelFun.Zoom
  alias Octopus.Installation
  alias Octopus.Sphere

  @tilt_defaults %{tilt_scale: 0.0, tilt_speed: 0.5, tilt_mode: :wobble}
  @zoom_factor_min 0.7

  @doc "Precompute `{x, y, direction}` triples per panel for the sphere sample path."
  def precompute_pixel_dirs do
    w = Installation.width()
    h = Installation.height()

    Installation.virtual_pixel_positions_per_panel()
    |> Enum.map(fn panel ->
      Enum.map(panel, fn {x, y} -> {x, y, Sphere.direction(x, y, w, h)} end)
    end)
  end

  @doc """
  Build motion params from an effective-values map (orbit/roll/tilt/elev/zoom + angles).

  `state` is a map or struct with the usual PixelFun sphere fields.
  `eff` is `%{orbit_rate, roll_rate, tilt_scale, elev_base, zoom_base, yaw_offset}`.
  """
  def build_motion_params(state, eff, seconds, opts \\ []) do
    w = Installation.width()
    alpha = Sphere.alpha(w)
    cx = w / 2 - 0.5
    cy = Installation.height() / 2 - 0.5

    orbit_rate = eff.orbit_rate
    roll_rate = eff.roll_rate
    tilt_scale = eff.tilt_scale
    elev_base = eff.elev_base
    z = max(eff.zoom_base || 1.0, @zoom_factor_min)

    yaw_angle = (Map.get(state, :yaw_angle) || orbit_rate * alpha * seconds) + eff.yaw_offset * alpha
    roll_angle = Map.get(state, :roll_angle) || roll_rate * :math.pi() / 180.0 * seconds

    frozen_scrub = Keyword.get(opts, :frozen_scrub)

    {yaw_angle, roll_angle} =
      if is_function(frozen_scrub, 3) do
        frozen_scrub.(yaw_angle, roll_angle, alpha)
      else
        {yaw_angle, roll_angle}
      end

    any_auto? = Keyword.get(opts, :any_auto?, false)
    zoom_octave_n = Map.get(state, :zoom_octave_n) || 0
    octave_fade = Map.get(state, :octave_fade)

    neutral? =
      orbit_rate == 0.0 and roll_rate == 0.0 and tilt_scale == 0.0 and elev_base == 0.0 and
        z == 1.0 and zoom_octave_n == 0 and octave_fade == nil and not any_auto? and
        yaw_angle == 0.0 and roll_angle == 0.0

    if neutral? do
      %{neutral?: true, center_x: cx, center_y: cy, alpha: alpha}
    else
      tilt_amp_rad = tilt_scale * alpha

      roll_pivot_panel =
        if Map.get(state, :rot_auto) do
          Map.get(state, :rot_auto_pivot) || Map.get(state, :roll_pivot) || 0
        else
          Map.get(state, :roll_pivot) || 0
        end

      roll_pivot_phi = panel_to_phi(roll_pivot_panel, w, alpha)
      zoom_pivot_phi = panel_to_phi(Map.get(state, :zoom_pivot) || 0, w, alpha)
      x_p = zoom_pivot_phi / alpha

      matrix =
        Sphere.orientation(
          yaw: yaw_angle,
          roll_angle: roll_angle,
          roll_pivot_phi: roll_pivot_phi,
          tilt_amplitude: tilt_amp_rad,
          tilt_speed: Map.get(state, :tilt_speed) || @tilt_defaults.tilt_speed,
          tilt_mode: Map.get(state, :tilt_mode) || @tilt_defaults.tilt_mode,
          t: seconds
        )

      %{
        neutral?: false,
        matrix: matrix,
        mobius_basis: Sphere.mobius_basis(zoom_pivot_phi),
        zoom_center: {:math.cos(zoom_pivot_phi), :math.sin(zoom_pivot_phi), 0.0},
        zoom_mode: coerce_zoom_mode(Map.get(state, :zoom_mode) || :mobius),
        elev_rad: Sphere.elev_offset(elev_base, alpha),
        alpha: alpha,
        center_x: cx,
        center_y: cy,
        x_p: x_p
      }
    end
  end

  @doc "Sample one zoom octave branch → `{xs, ys, direction}`."
  def sample_zoom_branch(motion_params, z, x, y, d, n) do
    m = Zoom.octave_factor(n)
    r = z / m

    if motion_params.neutral? do
      Sphere.sample(d, Map.merge(motion_params, %{x: x, y: y}))
    else
      Zoom.sample_pixel(d, motion_params, m, r, motion_params.x_p)
    end
  end

  @doc "Chart-only sample for tests / helpers → `{xs, ys}`."
  def sample_pixel(d, x, y, motion_params, z, n) do
    {xs, ys, _dir} = sample_zoom_branch(motion_params, z, x, y, d, n)
    {xs, ys}
  end

  def panel_to_phi(panel, w, alpha) do
    n = max(Installation.num_panels(), 1)
    panel = panel |> trunc() |> max(0) |> min(n - 1)
    stride = Installation.panel_width() + Installation.panel_gap()
    cx = w / 2 - 0.5
    center_x = panel * stride + Installation.panel_width() / 2 - 0.5
    (center_x - cx) * alpha
  end

  defp coerce_zoom_mode(:merlin), do: :merlin
  defp coerce_zoom_mode("merlin"), do: :merlin
  defp coerce_zoom_mode(_), do: :mobius
end
