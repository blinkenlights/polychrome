defmodule Octopus.Radar.PoseTweakTest do
  use ExUnit.Case, async: false

  alias Octopus.Radar.{PoseTweak, SensorPlan}

  @installation_radar [
    defaults: [sensitivity: :normal, height_cm: 500],
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

  setup do
    unless Process.whereis(PoseTweak) do
      start_supervised!(PoseTweak)
    end

    :ok
  end

  describe "normalize_deg/1" do
    test "wraps values into 0..360" do
      assert PoseTweak.normalize_deg(370) == 10.0
      assert PoseTweak.normalize_deg(-10) == 350.0
      assert PoseTweak.normalize_deg(360) == 0.0
      assert PoseTweak.normalize_deg(368) == 8.0
    end
  end

  describe "runtime state" do
    test "stores layout start and angle offset independently" do
      PoseTweak.set_layout_start_angle_deg(45)
      PoseTweak.set_angle_offset_deg(15)

      assert PoseTweak.layout_start_angle_deg() == 45.0
      assert PoseTweak.angle_offset_deg() == 15.0
    end

    test "stores per-sensor installation angles independently" do
      PoseTweak.set_sensor_installation_angle_deg(1, 12)
      PoseTweak.set_sensor_installation_angle_deg(3, 27)

      assert PoseTweak.sensor_installation_angle_deg(1) == 12.0
      assert PoseTweak.sensor_installation_angle_deg(3) == 27.0
      assert PoseTweak.sensor_installation_angle_deg(2) == 0.0
      assert PoseTweak.sensor_installation_angles() == %{1 => 12.0, 3 => 27.0}
    end
  end

  describe "pose tweak application" do
    test "angle offset belongs on rotation_deg, not angle_deg" do
      base = [
        angle_deg: 30.0,
        rotation_deg: 90.0,
        distance_cm: 300
      ]

      PoseTweak.set_angle_offset_deg(10.0)

      tweaked =
        if true do
          rotation =
            base
            |> Keyword.get(:rotation_deg, 0)
            |> Kernel.+(PoseTweak.angle_offset_deg())
            |> PoseTweak.normalize_deg()

          base
          |> Keyword.put(:rotation_deg, rotation)
        end

      assert Keyword.fetch!(tweaked, :angle_deg) == 30.0
      assert Keyword.fetch!(tweaked, :rotation_deg) == 100.0
    end

    test "per-sensor installation angle rotates local frame, not mount bearing" do
      base = [
        angle_deg: 30.0,
        rotation_deg: 90.0,
        distance_cm: 300
      ]

      PoseTweak.set_sensor_installation_angle_deg(2, 5.0)

      rotation =
        base
        |> Keyword.get(:rotation_deg, 0)
        |> Kernel.+(PoseTweak.sensor_installation_angle_deg(2))
        |> PoseTweak.normalize_deg()

      assert rotation == 95.0
      assert Keyword.fetch!(base, :angle_deg) == 30.0
    end

    test "per-sensor installation angle only rotates that sensor's local frame" do
      PoseTweak.set_sensor_installation_angle_deg(2, 7.0)

      configs = SensorPlan.build(@installation_radar, @deployment, :live)

      assert {1, cfg1} = Enum.at(configs, 0)
      assert {2, cfg2} = Enum.at(configs, 1)
      assert {3, cfg3} = Enum.at(configs, 2)

      assert cfg1[:angle_deg] == 0.0
      assert cfg2[:angle_deg] == 240.0
      assert cfg3[:angle_deg] == 120.0
      assert cfg1[:rotation_deg] == 180.0
      assert cfg2[:rotation_deg] == 187.0
      assert cfg3[:rotation_deg] == 180.0
    end
  end
end
