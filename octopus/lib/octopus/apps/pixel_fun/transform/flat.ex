defmodule Octopus.Apps.PixelFun.Transform.Flat do
  @moduledoc """
  Linear-installation transform: canvas-space translate, rotate, uniform zoom, sway.

  Used when `Installation.arrangement() == :linear`. No sphere / seamless wrap.
  """

  alias Octopus.Installation

  @doc """
  Transform canvas pixel `(x, y)` into formula coordinates.

  Params:
  - `:offset_x` / `:offset_y` — pan including animated translate
  - `:zoom` — uniform scale factor (1.0 = identity)
  - `:seconds` — signed formula clock
  - `:rotation` — absolute canvas rotation in radians. The caller integrates the
    manual `rotate_scale` rate, or substitutes the rot-auto sweep angle.
  - `:sway_scale` / `:sway_speed` / `:sway_mode` — `Octopus.Sway` on Y
  """
  def transform_pixel_coords(x, y, params) do
    %{
      offset_x: offset_x,
      offset_y: offset_y,
      zoom: zoom,
      seconds: seconds,
      rotation: rotation,
      sway_scale: sway_scale,
      sway_speed: sway_speed,
      sway_mode: sway_mode
    } = params

    w = Installation.width()
    center_x = w / 2 - 0.5
    center_y = Installation.height() / 2 - 0.5

    {x_scaled, y_scaled} =
      rotate_and_zoom(x, y, offset_x, offset_y, center_x, center_y, rotation, zoom)

    y_final =
      if sway_scale == 0.0 do
        y_scaled
      else
        {sway_amplitude, sway_phase} =
          Octopus.Sway.params(sway_scale, sway_speed, sway_mode, seconds)

        y_scaled + Octopus.Sway.offset(x, w, sway_amplitude, sway_phase)
      end

    {x_scaled, y_final}
  end

  @doc """
  Absolute rotation angle (rad) produced by the manual `roll_rate` in °/s.

  Rot auto bypasses this and supplies an eased sweep angle instead, so that a
  preset sweeps by the same number of degrees here as it does on a ring.
  """
  def rotation_angle(roll_rate, seconds) when is_number(roll_rate) and is_number(seconds),
    do: seconds * roll_rate * :math.pi() / 180.0

  @doc "Animated translate offset from `translate_scale` plus optional base `{ox, oy}`."
  def translate_offset(translate_scale, seconds, offset \\ {0.0, 0.0})

  def translate_offset(scale, seconds, {ox, oy}) when is_number(scale) and is_number(seconds) do
    anim_x = :math.sin(0.3 + seconds * 0.17) * scale
    anim_y = :math.cos(0.7 + seconds * 0.05) * scale
    {ox + anim_x, oy + anim_y}
  end

  defp rotate_and_zoom(x, y, offset_x, offset_y, center_x, center_y, rotation, zoom) do
    x_translated = x - offset_x - center_x
    y_translated = y - offset_y - center_y

    x_rotated = x_translated * :math.cos(rotation) - y_translated * :math.sin(rotation)
    y_rotated = x_translated * :math.sin(rotation) + y_translated * :math.cos(rotation)

    # Uniform scale — no Y-only distortion.
    {x_rotated * zoom, y_rotated * zoom}
  end
end
