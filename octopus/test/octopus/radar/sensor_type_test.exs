defmodule Octopus.Radar.SensorTypeTest do
  use ExUnit.Case, async: true

  alias Octopus.Radar.{SensorType, Track}

  describe "ld6001a coordinate convention" do
    test "negates y and vy in to_canonical/2" do
      track = %Track{
        id: 1,
        reserved: 0,
        x: 1.0,
        y: 2.0,
        z: 1.7,
        vx: 0.3,
        vy: -0.4,
        vz: 0.0
      }

      canonical = SensorType.to_canonical(:ld6001a, track)

      assert canonical.x == 1.0
      assert canonical.y == -2.0
      assert canonical.vx == 0.3
      assert canonical.vy == 0.4
    end

    test "from_canonical/2 inverts to_canonical/2" do
      track = %Track{
        id: 1,
        reserved: 0,
        x: 1.0,
        y: 2.0,
        z: 1.7,
        vx: 0.3,
        vy: -0.4,
        vz: 0.0
      }

      round_trip = track |> then(&SensorType.to_canonical(:ld6001a, &1)) |> then(&SensorType.from_canonical(:ld6001a, &1))

      assert round_trip.x == track.x
      assert round_trip.y == track.y
      assert round_trip.vx == track.vx
      assert round_trip.vy == track.vy
    end
  end

  describe "resolve_sensitivity/2 for :ld6001a" do
    test "presets map to vendor-oriented DPKTH values" do
      assert SensorType.resolve_sensitivity(:ld6001a, :normal) == 4
      assert SensorType.resolve_sensitivity(:ld6001a, :lower) == 6
      assert SensorType.resolve_sensitivity(:ld6001a, :higher) == 2
    end

    test "explicit device values pass through when in range" do
      assert SensorType.resolve_sensitivity(:ld6001a, 7) == 7
    end

    test "rejects invalid settings" do
      assert_raise ArgumentError, fn ->
        SensorType.resolve_sensitivity(:ld6001a, :unknown)
      end

      assert_raise ArgumentError, fn ->
        SensorType.resolve_sensitivity(:ld6001a, 0)
      end
    end
  end

  describe "UI sensitivity level" do
    test "level 1 is least sensitive and level 9 is most sensitive" do
      assert SensorType.sensitivity_level(:ld6001a, 9) == 1
      assert SensorType.sensitivity_level(:ld6001a, 1) == 9
      assert SensorType.level_to_device_value(:ld6001a, 1) == 9
      assert SensorType.level_to_device_value(:ld6001a, 9) == 1
    end

    test ":normal preset is level 6 on the UI scale" do
      normal = SensorType.resolve_sensitivity(:ld6001a, :normal)
      assert SensorType.sensitivity_level(:ld6001a, normal) == 6
    end
  end
end
