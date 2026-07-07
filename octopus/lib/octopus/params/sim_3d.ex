defmodule Octopus.Params.Sim3d do
  use Octopus.Params, prefix: :sim_3d

  def topic, do: "sim_3d"

  def diameter, do: param(:diameter, 20.0)
  def move, do: param(:move, [0.0, 0.0])
  def position, do: param(:position, [0.0, 0.0])
  def height, do: param(:height, 0.4)
  def pole_diameter, do: param(:pole_diameter, 0.15)
  def foot_diameter, do: param(:foot_diameter, 0.3)
  def button_diameter, do: param(:button_diameter, 5.0)
  def radar_count, do: param(:radar_count, 6)

  def radar_height, do: param(:radar_height, 4.5)
  def radar_tilt_deg, do: param(:radar_tilt_deg, 15.0)
  def radar_arm_length_m, do: param(:radar_arm_length_m, 3.0)
  def mast_diameter_m, do: param(:mast_diameter_m, 0.35)
  def platform_radius_m, do: param(:platform_radius_m, 2.5)
  def lean_post_bottom_r, do: param(:lean_post_bottom_r, 0.5)
  def lean_post_top_r, do: param(:lean_post_top_r, 0.1)
  def lean_post_height, do: param(:lean_post_height, 1.2)
  def render_radar_cones, do: param(:render_radar_cones, false)
  def radar_cone_straight_down, do: param(:radar_cone_straight_down, true)

  @doc """
  Ordered config schema for the web UI (keyword list keeps the render order).
  """
  def config_schema do
    [
      diameter:
        {"Durchmesser (m)", :float, %{default: 20.0, min: 10.0, max: 20.0, step: 0.1, group: "Panels"}},
      radar_count: {"Anzahl Sensoren", :int, %{default: 6, min: 4, max: 12, step: 2, group: "Radar"}},
      radar_height:
        {"Höhe (m)", :float, %{default: 4.5, min: 0.5, max: 12.0, step: 0.05, group: "Radar"}},
      radar_tilt_deg:
        {"Neigung (°)", :float, %{default: 15.0, min: 0.0, max: 90.0, step: 1.0, group: "Radar"}},
      radar_cone_straight_down:
        {"Senkrecht n. unten", :boolean, %{default: true, group: "Radar"}},
      radar_arm_length_m:
        {"Latten-Länge (m)", :float, %{default: 3.0, min: 0.0, max: 8.0, step: 0.01, group: "Radar"}},
      mast_diameter_m:
        {"Mast-Ø (m)", :float, %{default: 0.35, min: 0.05, max: 0.5, step: 0.005, group: "Radar"}},
      render_radar_cones: {"Licht-Kegel", :boolean, %{default: false, group: "Radar"}},
      platform_radius_m:
        {"Plattform-Radius (m)", :float,
         %{default: 2.5, min: 0.5, max: 3.0, step: 0.05, group: "Plattform & Rückenlehne"}},
      lean_post_bottom_r:
        {"Lehne Ø unten (m)", :float,
         %{default: 0.5, min: 0.1, max: 2.5, step: 0.01, group: "Plattform & Rückenlehne"}},
      lean_post_top_r:
        {"Lehne Ø oben (m)", :float,
         %{default: 0.1, min: 0.02, max: 2.5, step: 0.01, group: "Plattform & Rückenlehne"}},
      lean_post_height:
        {"Lehne Höhe (m)", :float,
         %{default: 1.2, min: 0.2, max: 3.0, step: 0.01, group: "Plattform & Rückenlehne"}}
    ]
  end

  @doc """
  Current Sim3D config for the web UI.
  """
  def config do
    %{
      diameter: diameter(),
      radar_count: radar_count(),
      radar_height: radar_height(),
      radar_tilt_deg: radar_tilt_deg(),
      radar_arm_length_m: radar_arm_length_m(),
      mast_diameter_m: mast_diameter_m(),
      platform_radius_m: platform_radius_m(),
      lean_post_bottom_r: lean_post_bottom_r(),
      lean_post_top_r: lean_post_top_r(),
      lean_post_height: lean_post_height(),
      render_radar_cones: render_radar_cones(),
      radar_cone_straight_down: radar_cone_straight_down()
    }
  end

  @doc """
  Update Sim3D parameters from the web UI. Persists into the params store and
  broadcasts on `topic/0` so the live 3D view picks up the change.
  """
  def update_config(config) do
    Enum.each(config, fn {key, value} ->
      Octopus.Params.put("sim_3d", Atom.to_string(key), value)
      handle_param(Atom.to_string(key), [value])
    end)
  end

  def subscribe do
    Phoenix.PubSub.subscribe(Octopus.PubSub, topic())
  end

  def handle_param("diameter", [value]) do
    Phoenix.PubSub.broadcast(Octopus.PubSub, topic(), {:diameter, value})
  end

  def handle_param("move", [x, y]) do
    Phoenix.PubSub.broadcast(Octopus.PubSub, topic(), {:move, [x, y]})
  end

  def handle_param("position", [x, y]) do
    Phoenix.PubSub.broadcast(Octopus.PubSub, topic(), {:position, [x, y]})
  end

  def handle_param("height", [value]) do
    Phoenix.PubSub.broadcast(Octopus.PubSub, topic(), {:height, value})
  end

  def handle_param("pole_diameter", [value]) do
    Phoenix.PubSub.broadcast(Octopus.PubSub, topic(), {:pole_diameter, value})
  end

  def handle_param("foot_diameter", [value]) do
    Phoenix.PubSub.broadcast(Octopus.PubSub, topic(), {:foot_diameter, value})
  end

  def handle_param("button_diameter", [value]) do
    Phoenix.PubSub.broadcast(Octopus.PubSub, topic(), {:button_diameter, value})
  end

  def handle_param("radar_count", [value]) do
    Phoenix.PubSub.broadcast(Octopus.PubSub, topic(), {:radar_count, value})
  end

  def handle_param("radar_height", [value]) do
    Phoenix.PubSub.broadcast(Octopus.PubSub, topic(), {:radar_height, value})
  end

  def handle_param("radar_tilt_deg", [value]) do
    Phoenix.PubSub.broadcast(Octopus.PubSub, topic(), {:radar_tilt_deg, value})
  end

  def handle_param("radar_arm_length_m", [value]) do
    Phoenix.PubSub.broadcast(Octopus.PubSub, topic(), {:radar_arm_length_m, value})
  end

  def handle_param("mast_diameter_m", [value]) do
    Phoenix.PubSub.broadcast(Octopus.PubSub, topic(), {:mast_diameter_m, value})
  end

  def handle_param("platform_radius_m", [value]) do
    Phoenix.PubSub.broadcast(Octopus.PubSub, topic(), {:platform_radius_m, value})
  end

  def handle_param("lean_post_bottom_r", [value]) do
    Phoenix.PubSub.broadcast(Octopus.PubSub, topic(), {:lean_post_bottom_r, value})
  end

  def handle_param("lean_post_top_r", [value]) do
    Phoenix.PubSub.broadcast(Octopus.PubSub, topic(), {:lean_post_top_r, value})
  end

  def handle_param("lean_post_height", [value]) do
    Phoenix.PubSub.broadcast(Octopus.PubSub, topic(), {:lean_post_height, value})
  end

  def handle_param("render_radar_cones", [value]) do
    Phoenix.PubSub.broadcast(Octopus.PubSub, topic(), {:render_radar_cones, value})
  end

  def handle_param("radar_cone_straight_down", [value]) do
    Phoenix.PubSub.broadcast(Octopus.PubSub, topic(), {:radar_cone_straight_down, value})
  end

  def handle_param(_key, _value), do: :ignore
end
