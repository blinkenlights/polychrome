defmodule Octopus.Radar.TransformTest do
  use ExUnit.Case, async: true

  alias Octopus.Radar.{Frame, Track, Transform}

  @base_config [
    angle_deg: 0,
    distance_cm: 0,
    rotation_deg: 0
  ]

  defp track(overrides \\ []) do
    struct(
      %Track{
        id: 1,
        reserved: 0,
        x: 0.0,
        y: 0.0,
        z: 1.7,
        vx: 0.0,
        vy: 0.0,
        vz: 0.0
      },
      overrides
    )
  end

  describe "transform_track/2" do
    test "identity transform leaves coordinates unchanged" do
      t = track(x: 1.5, y: -0.3, vx: 0.2, vy: -0.1, z: 1.7, vz: 0.05)
      result = Transform.transform_track(t, @base_config)

      assert result.x == t.x
      assert result.y == t.y
      assert result.vx == t.vx
      assert result.vy == t.vy
      assert result.z == t.z
      assert result.vz == t.vz
    end

    test "pure translation along +X" do
      config = Keyword.merge(@base_config, distance_cm: 100, angle_deg: 0)
      result = Transform.transform_track(track(x: 1.0, y: 0.0), config)

      assert_in_delta result.x, 2.0, 1.0e-6
      assert_in_delta result.y, 0.0, 1.0e-6
    end

    test "sensor on +Y beam (90°) translates and rotates local frame by 90°" do
      # rotation_deg: 0 with angle_deg: 90 → effective rotation = 90°.
      # Mount at (0, 0.5 m). Local (0, 1) with 90° rotation:
      #   x_global = 0 + 0*cos90 - 1*sin90 = -1.0
      #   y_global = 0.5 + 0*sin90 + 1*cos90 = 0.5
      config = Keyword.merge(@base_config, distance_cm: 50, angle_deg: 90)
      result = Transform.transform_track(track(x: 0.0, y: 1.0), config)

      assert_in_delta result.x, -1.0, 1.0e-6
      assert_in_delta result.y, 0.5, 1.0e-6
    end

    test "pure 90° CCW rotation" do
      config = Keyword.merge(@base_config, rotation_deg: 90)
      result = Transform.transform_track(track(x: 1.0, y: 0.0, vx: 1.0, vy: 0.0), config)

      assert_in_delta result.x, 0.0, 1.0e-6
      assert_in_delta result.y, 1.0, 1.0e-6
      assert_in_delta result.vx, 0.0, 1.0e-6
      assert_in_delta result.vy, 1.0, 1.0e-6
    end

    test "rotation and translation combined" do
      config = Keyword.merge(@base_config, distance_cm: 100, angle_deg: 0, rotation_deg: 90)
      result = Transform.transform_track(track(x: 1.0, y: 0.0), config)

      assert_in_delta result.x, 1.0, 1.0e-6
      assert_in_delta result.y, 1.0, 1.0e-6
    end

    test "global origin target maps to expected local coords (inverse check)" do
      config = Keyword.merge(@base_config, distance_cm: 100, angle_deg: 0, rotation_deg: 45)

      {tx, ty, cos_r, sin_r} = Transform.pose_factors(config)

      # Local coords that should map to global (0, 0): R(-θ) * (-tx, -ty)
      local_x = cos_r * (-tx) + sin_r * (-ty)
      local_y = -sin_r * (-tx) + cos_r * (-ty)

      result = Transform.transform_track(track(x: local_x, y: local_y), config)

      assert_in_delta result.x, 0.0, 1.0e-6
      assert_in_delta result.y, 0.0, 1.0e-6
    end

    test "rotation_deg is relative to beam — sensor on 90° beam with rotation_deg 0 rotates local by 90°" do
      # Sensor at angle 90°, no distance offset, rotation_deg 0 (aligned with beam outward).
      # Effective rotation = 90° + 0° = 90° CCW.
      # Local +X should map to global +Y.
      config = Keyword.merge(@base_config, angle_deg: 90, distance_cm: 0, rotation_deg: 0)
      result = Transform.transform_track(track(x: 1.0, y: 0.0, vx: 1.0, vy: 0.0), config)

      assert_in_delta result.x, 0.0, 1.0e-6
      assert_in_delta result.y, 1.0, 1.0e-6
      assert_in_delta result.vx, 0.0, 1.0e-6
      assert_in_delta result.vy, 1.0, 1.0e-6
    end

    test "inward-facing sensor on 90° beam (rotation_deg 180) maps local +X to global origin" do
      # Sensor mounted 100 cm along the 90° beam (at global (0, 1.0 m)), facing inward.
      # Effective rotation = 90° + 180° = 270°.
      # An object 1 m in front of the sensor (local (1, 0)) should land at the center (0, 0).
      config = Keyword.merge(@base_config, angle_deg: 90, distance_cm: 100, rotation_deg: 180)
      result = Transform.transform_track(track(x: 1.0, y: 0.0), config)

      assert_in_delta result.x, 0.0, 1.0e-6
      assert_in_delta result.y, 0.0, 1.0e-6
    end

    test "rotation_deg correction shifts beam-relative orientation by that many degrees" do
      # Sensor on 0° beam, rotation_deg 5 means 5° CCW from outward direction.
      # Effective rotation = 0° + 5° = 5°. Local +X should tilt 5° toward +Y.
      config = Keyword.merge(@base_config, angle_deg: 0, distance_cm: 0, rotation_deg: 5)
      result = Transform.transform_track(track(x: 1.0, y: 0.0), config)

      assert_in_delta result.x, :math.cos(5 * :math.pi() / 180), 1.0e-6
      assert_in_delta result.y, :math.sin(5 * :math.pi() / 180), 1.0e-6
    end
  end

  describe "global_to_local_track/2 — inverse of transform_track/2" do
    @poses [
      [angle_deg: 0, distance_cm: 0, rotation_deg: 0],
      [angle_deg: 0, distance_cm: 150, rotation_deg: 180],
      [angle_deg: 90, distance_cm: 150, rotation_deg: 180],
      [angle_deg: 217, distance_cm: 220, rotation_deg: 7],
      [angle_deg: 45, distance_cm: 100, rotation_deg: 90]
    ]

    test "global → local → global is the identity across poses" do
      global = track(x: 2.3, y: -1.4, z: 1.72, vx: 0.4, vy: -0.25, vz: 0.0)

      for pose <- @poses do
        local = Transform.global_to_local_track(global, pose)
        round_trip = Transform.transform_track(local, pose)

        assert_in_delta round_trip.x, global.x, 1.0e-6
        assert_in_delta round_trip.y, global.y, 1.0e-6
        assert_in_delta round_trip.vx, global.vx, 1.0e-6
        assert_in_delta round_trip.vy, global.vy, 1.0e-6
        assert round_trip.z == global.z
        assert round_trip.id == global.id
      end
    end

    test "different sensors reconstruct the same global coordinate (agreement)" do
      global = track(x: 1.0, y: 0.5, z: 1.7)

      reconstructed =
        Enum.map(@poses, fn pose ->
          local = Transform.global_to_local_track(global, pose)
          Transform.transform_track(local, pose)
        end)

      Enum.each(reconstructed, fn r ->
        assert_in_delta r.x, global.x, 1.0e-6
        assert_in_delta r.y, global.y, 1.0e-6
      end)
    end
  end

  describe "transform_frame/2" do
    test "transforms all tracks in a frame" do
      config = Keyword.merge(@base_config, distance_cm: 100, angle_deg: 0)

      frame = %Frame{
        frame_number: 42,
        received_at: 1,
        tracks: [track(x: 1.0, y: 0.0), track(x: 0.0, y: 2.0, id: 2)]
      }

      result = Transform.transform_frame(frame, config)

      assert result.frame_number == 42
      assert length(result.tracks) == 2
      assert_in_delta hd(result.tracks).x, 2.0, 1.0e-6
      assert_in_delta hd(result.tracks).y, 0.0, 1.0e-6
      assert_in_delta Enum.at(result.tracks, 1).x, 1.0, 1.0e-6
      assert_in_delta Enum.at(result.tracks, 1).y, 2.0, 1.0e-6
    end
  end
end
