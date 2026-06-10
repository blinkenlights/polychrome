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

    test "pure translation along +Y" do
      config = Keyword.merge(@base_config, distance_cm: 50, angle_deg: 90)
      result = Transform.transform_track(track(x: 0.0, y: 1.0), config)

      assert_in_delta result.x, 0.0, 1.0e-6
      assert_in_delta result.y, 1.5, 1.0e-6
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
