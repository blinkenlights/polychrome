defmodule Octopus.Installation.World do
  @moduledoc """
  Static world description derived from the active installation config.

  Suitable as the single geometry source for radar views, proximity math, or a
  3D scene. Coordinates:

    * Ground plane: `x` left/right (east +), `y` front/back (north +)
    * Up: `z` (meters above ground)
    * Panel angles: clockwise from north (`+Y`), matching `panel_positions_m/1`
    * Sensor bearings: from `+X`, counter-clockwise (see `sensor_mount_m/2`)
  """

  alias Octopus.Hardware.PanelSlot
  alias Octopus.Installation
  alias Octopus.Radar.SensorPlan

  @type t :: %{
          arrangement: :circular | :linear,
          location: term(),
          axes: map(),
          ring: map() | nil,
          panel_type: atom() | nil,
          panel_size_m: map() | nil,
          panels: [map()],
          sensors: [map()],
          counts: map()
        }

  @doc """
  Full world snapshot for the active installation.

  ## Options

    * `:north_panel` — override ring orientation (defaults to installation config)
  """
  @spec describe(keyword()) :: t()
  def describe(opts \\ []) when is_list(opts) do
    arrangement = Installation.arrangement()
    north = Keyword.get(opts, :north_panel, Installation.north_panel())
    size = panel_size_m()
    bottom_m = Installation.panel_bottom_m()

    %{
      arrangement: arrangement,
      location: Installation.location(),
      axes: axes(),
      ring: ring(arrangement, north, bottom_m),
      panel_type: Installation.panel_type(),
      panel_size_m: size,
      panels: panels(arrangement, north, size, bottom_m),
      sensors: sensors(),
      counts: %{
        panels: Installation.num_panels(),
        buttons: Installation.num_buttons(),
        joysticks: Installation.num_joysticks()
      }
    }
  end

  defp axes do
    %{
      ground_x: "+east / left-right",
      ground_y: "+north / front-back",
      up_z: "+up",
      panel_theta: "clockwise from +Y (north)",
      sensor_bearing: "counter-clockwise from +X"
    }
  end

  defp ring(:linear, _north, _bottom_m), do: nil

  defp ring(:circular, north, bottom_m) do
    n = Installation.num_panels()

    %{
      radius_m: Installation.ring_radius_m(),
      north_panel: north,
      platform_radius_m: Installation.platform_radius_m(),
      panel_bottom_m: bottom_m,
      step_deg: 360.0 / n
    }
  end

  defp panel_size_m do
    case Installation.panel_outer_dimensions_cm() do
      {w, h, d} ->
        %{width_m: w / 100.0, height_m: h / 100.0, depth_m: d / 100.0}

      _ ->
        nil
    end
  end

  defp panels(:linear, _north, size, bottom_m) do
    slots = Installation.panel_slots()

    Enum.with_index(slots, 1)
    |> Enum.map(fn {slot, n} ->
      base_panel(n, slot, size, bottom_m)
      |> Map.merge(%{
        x: nil,
        y: nil,
        z: center_z(bottom_m, size),
        theta_deg: nil,
        theta_rad: nil,
        offset: nil,
        inner_face: nil,
        body_center: nil
      })
    end)
  end

  defp panels(:circular, north, size, bottom_m) do
    slots = Installation.panel_slots()
    body = positions_by_panel(reference: :body_center, north_panel: north)
    inner = positions_by_panel(reference: :inner_face, north_panel: north)

    Enum.with_index(slots, 1)
    |> Enum.map(fn {slot, n} ->
      b = Map.fetch!(body, n)
      i = Map.fetch!(inner, n)

      base_panel(n, slot, size, bottom_m)
      |> Map.merge(%{
        x: b.x,
        y: b.y,
        z: center_z(bottom_m, size),
        theta_deg: b.theta_deg,
        theta_rad: b.theta_rad,
        offset: b.offset,
        # Faces inward toward ring center; yaw around +Z (up).
        facing_rad: b.theta_rad + :math.pi(),
        bottom_z_m: bottom_m,
        top_z_m: top_z(bottom_m, size),
        body_center: %{x: b.x, y: b.y, z: center_z(bottom_m, size)},
        inner_face: %{x: i.x, y: i.y, z: center_z(bottom_m, size)}
      })
    end)
  end

  defp base_panel(n, %PanelSlot{} = slot, size, bottom_m) do
    %{
      panel: n,
      controller: slot.controller_id,
      wiring: slot.wiring_id,
      size_m: size,
      bottom_z_m: bottom_m,
      top_z_m: top_z(bottom_m, size)
    }
  end

  defp positions_by_panel(opts) do
    Installation.panel_positions_m(opts)
    |> Map.new(&{&1.panel, &1})
  end

  defp center_z(nil, _), do: nil
  defp center_z(_bottom, nil), do: nil
  defp center_z(bottom_m, %{height_m: h}), do: bottom_m + h / 2.0

  defp top_z(nil, _), do: nil
  defp top_z(_bottom, nil), do: nil
  defp top_z(bottom_m, %{height_m: h}), do: bottom_m + h

  defp sensors do
    Installation.radar_config()
    |> SensorPlan.build_static()
    |> Enum.map(fn {device_id, config} ->
      angle_deg = Keyword.fetch!(config, :angle_deg)
      distance_cm = Keyword.fetch!(config, :distance_cm)
      height_cm = Keyword.get(config, :height_cm, 0)
      {x, y} = Installation.sensor_mount_m(angle_deg, distance_cm)

      %{
        device_id: device_id,
        sensor_id: Keyword.get(config, :sensor_id),
        type: Keyword.get(config, :type),
        angle_deg: angle_deg,
        distance_cm: distance_cm,
        rotation_deg: Keyword.get(config, :rotation_deg, 0),
        height_cm: height_cm,
        range_cm: Keyword.get(config, :range_cm),
        x: x,
        y: y,
        z: height_cm / 100.0,
        enabled: Keyword.get(config, :enabled, true)
      }
    end)
  end
end
