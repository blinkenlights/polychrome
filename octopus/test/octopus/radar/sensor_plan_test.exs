defmodule Octopus.Radar.SensorPlanTest do
  use ExUnit.Case, async: true

  alias Octopus.Radar.SensorPlan

  @installation_radar [
    defaults: [sensitivity: 4, height_cm: 500],
    layout: [
      type: :radial,
      sensors: [:a, :b, :c],
      start_angle_deg: 0,
      distance_cm: 300,
      rotation_deg: 180
    ]
  ]

  @deployment [
    defaults: [type: :ld6001a, baud: 115_200],
    sensors: [
      [id: :a, port: "/dev/ttyUSB0"],
      [id: :b, port: "/dev/ttyUSB1"],
      [id: :c, port: "/dev/ttyUSB2"]
    ]
  ]

  describe "deployment_bound?/2" do
    test "false when installation has no radar" do
      refute SensorPlan.deployment_bound?(nil, @deployment)
    end

    test "false when deployment is nil" do
      refute SensorPlan.deployment_bound?(@installation_radar, nil)
    end

    test "false when a sensor id is missing from deployment" do
      partial = Keyword.put(@deployment, :sensors, [[id: :a, port: "/dev/ttyUSB0"]])
      refute SensorPlan.deployment_bound?(@installation_radar, partial)
    end

    test "true when every installation sensor id has a port" do
      assert SensorPlan.deployment_bound?(@installation_radar, @deployment)
    end
  end

  describe "build/3" do
    test "returns empty list when installation has no radar" do
      assert SensorPlan.build(nil, @deployment, :live) == []
    end

    test "live mode uses deployment ports and radial angles" do
      configs = SensorPlan.build(@installation_radar, @deployment, :live)

      assert length(configs) == 3

      assert {1, cfg1} = Enum.at(configs, 0)
      assert cfg1[:sensor_id] == :a
      assert cfg1[:port] == "/dev/ttyUSB0"
      assert cfg1[:angle_deg] == 0.0
      assert cfg1[:distance_cm] == 300
      assert cfg1[:rotation_deg] == 180

      assert {2, cfg2} = Enum.at(configs, 1)
      assert cfg2[:angle_deg] == 240.0

      assert {3, cfg3} = Enum.at(configs, 2)
      assert cfg3[:angle_deg] == 120.0
      assert cfg3[:port] == "/dev/ttyUSB2"
    end

    test "mock mode uses synthetic ports without deployment bindings" do
      configs = SensorPlan.build(@installation_radar, nil, :exact)

      assert length(configs) == 3
      assert {1, cfg} = hd(configs)
      assert cfg[:port] == "/dev/tty.mock-radar-1"
      assert cfg[:type] == :ld6001a
    end

    test "live mode without deployment binding uses unbound placeholder ports" do
      configs = SensorPlan.build(@installation_radar, nil, :live)

      assert {1, cfg} = hd(configs)
      assert cfg[:port] == "/dev/tty.unbound-1"
    end
  end
end
