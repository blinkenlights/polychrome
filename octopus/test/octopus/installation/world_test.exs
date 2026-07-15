defmodule Octopus.Installation.WorldTest do
  use ExUnit.Case, async: false

  alias Octopus.Installation
  alias Octopus.Installation.{Nation2025, Nation2026, World}

  setup do
    prev = Application.fetch_env!(:octopus, :installation)
    on_exit(fn -> Application.put_env(:octopus, :installation, prev) end)
    :ok
  end

  test "Nation2025 and Nation2026 declare 40 cm panel bottom height" do
    assert Nation2025.panel_bottom_m() == 0.4
    assert Nation2026.panel_bottom_m() == 0.4
  end

  test "world_m exposes ring, panels with angles, and sensors for Nation2026" do
    Application.put_env(:octopus, :installation, Nation2026)

    world = Installation.world_m()

    assert world.arrangement == :circular
    assert world.ring.radius_m == 10.0
    assert world.ring.north_panel == 10
    assert world.ring.panel_bottom_m == 0.4
    assert world.ring.platform_radius_m == 2.25

    assert world.panel_type == :polychrome
    assert_in_delta world.panel_size_m.height_m, 1.56, 0.01

    assert length(world.panels) == 12
    north = Enum.find(world.panels, &(&1.panel == 10))
    assert_in_delta north.x, 0.0, 1.0e-6
    assert north.y > 0.0
    assert_in_delta north.theta_deg, 0.0, 1.0e-6
    assert_in_delta north.bottom_z_m, 0.4, 1.0e-6
    assert_in_delta north.z, 0.4 + world.panel_size_m.height_m / 2.0, 1.0e-6

    assert length(world.sensors) == 6
    sensor_a = Enum.find(world.sensors, &(&1.sensor_id == :a))
    assert is_float(sensor_a.x)
    assert is_float(sensor_a.y)
    assert_in_delta sensor_a.z, 5.0, 1.0e-6

    assert World.describe() == world
  end

  test "world_m respects north_panel override" do
    Application.put_env(:octopus, :installation, Nation2026)

    world = Installation.world_m(north_panel: 1)
    assert world.ring.north_panel == 1

    panel1 = Enum.find(world.panels, &(&1.panel == 1))
    assert_in_delta panel1.theta_deg, 0.0, 1.0e-6
  end
end
