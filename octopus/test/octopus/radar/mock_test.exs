defmodule Octopus.Radar.MockTest do
  use ExUnit.Case, async: false

  alias Octopus.Radar.{Frame, Protocol, Transform}
  alias Octopus.Radar.Mock.{Server, World}

  # Two sensors at different poses but observing the same shared world.
  @pose_a [angle_deg: 0, distance_cm: 150, rotation_deg: 180, range_cm: 1500]
  @pose_b [angle_deg: 120, distance_cm: 150, rotation_deg: 180, range_cm: 1500]

  describe "exact-mode cross-sensor agreement (math level)" do
    test "two poses both reconstruct the same global coordinate" do
      global =
        struct(%Octopus.Radar.Track{
          id: 1,
          reserved: 0,
          x: 1.2,
          y: -0.8,
          z: 1.7,
          vx: 0.3,
          vy: 0.1,
          vz: 0.0
        })

      for pose <- [@pose_a, @pose_b] do
        # The mock would encode the local track and the sensor parses + applies
        # the forward transform — replicate that chain here.
        local = Transform.global_to_local_track(global, pose)
        frame = %Frame{frame_number: 0, received_at: 0, tracks: [local]}

        {:ok, decoded} = Protocol.parse_frame(Protocol.encode_frame(frame))
        [reconstructed] = Transform.transform_frame(decoded, pose).tracks

        assert_in_delta reconstructed.x, global.x, 1.0e-3
        assert_in_delta reconstructed.y, global.y, 1.0e-3
      end
    end
  end

  describe "Mock.Server emits frames that reconstruct world objects" do
    setup do
      start_supervised!({World, [radius_m: 10.0, mode: :exact]})
      :ok = World.set_objects([%{id: 1, x: 2.0, y: 1.0, z: 1.7}])
      :ok
    end

    test "stays silent until AT+START, then streams reconstructable frames" do
      server_a = start_server(@pose_a)
      :ok = Server.attach(server_a, self(), "mock-a")

      # No frames before AT+START.
      refute_receive {:circuits_uart, "mock-a", _}, 300

      # AT+START is acknowledged and begins streaming.
      :ok = Server.write(server_a, "AT+START\n")
      assert_receive {:circuits_uart, "mock-a", "AT+OK\r\n"}, 500

      frame_a = await_frame("mock-a")
      [track_a] = Transform.transform_frame(frame_a, @pose_a).tracks

      assert_in_delta track_a.x, 2.0, 1.0e-2
      assert_in_delta track_a.y, 1.0, 1.0e-2
    end

    test "two sensors report the same global coordinate for the same object" do
      server_a = start_server(@pose_a)
      server_b = start_server(@pose_b)

      :ok = Server.attach(server_a, self(), "mock-a")
      :ok = Server.attach(server_b, self(), "mock-b")
      :ok = Server.write(server_a, "AT+START\n")
      :ok = Server.write(server_b, "AT+START\n")

      [track_a] = Transform.transform_frame(await_frame("mock-a"), @pose_a).tracks
      [track_b] = Transform.transform_frame(await_frame("mock-b"), @pose_b).tracks

      assert_in_delta track_a.x, track_b.x, 1.0e-2
      assert_in_delta track_a.y, track_b.y, 1.0e-2
      assert_in_delta track_a.x, 2.0, 1.0e-2
      assert_in_delta track_a.y, 1.0, 1.0e-2
    end
  end

  describe "platform chill behavior" do
    test "tracks the Sim3D platform radius and clamps it inside the world" do
      start_supervised!({World, [radius_m: 10.0, mode: :off]})

      broadcast_platform_radius(1.5)
      assert %{platform_radius_m: 1.5} = :sys.get_state(World)

      # An absurd radius is clamped strictly inside the world disk.
      broadcast_platform_radius(999.0)
      assert :sys.get_state(World).platform_radius_m < 10.0
    end

    test "ignores unrelated Sim3D parameter broadcasts" do
      pid = start_supervised!({World, [radius_m: 10.0, mode: :off]})

      Phoenix.PubSub.broadcast(Octopus.PubSub, Octopus.Params.Sim3d.topic(), {:diameter, 12.0})
      Phoenix.PubSub.broadcast(Octopus.PubSub, Octopus.Params.Sim3d.topic(), {:radar_height, 4.0})

      # Still responsive and alive — the catch-all clause swallowed them.
      assert is_map(:sys.get_state(World))
      assert Process.alive?(pid)
    end

    test "people stay inside the world disk at plausible heights" do
      radius = 6.0
      start_supervised!({World, [radius_m: radius, mode: :exact, max_people: 8, entropy: 40]})

      # The simulation is time-driven; let a handful of 100 ms ticks run so the
      # population spawns and moves before sampling the ground truth.
      Process.sleep(600)
      objects = World.objects()

      assert objects != []

      for o <- objects do
        assert :math.sqrt(o.x * o.x + o.y * o.y) <= radius + 1.0e-6
        assert o.z >= 0.6 and o.z <= 1.9
      end
    end
  end

  ## Helpers

  defp broadcast_platform_radius(value) do
    Phoenix.PubSub.broadcast(
      Octopus.PubSub,
      Octopus.Params.Sim3d.topic(),
      {:platform_radius_m, value}
    )

    # Force a synchronous round-trip so the broadcast is processed before we read.
    _ = :sys.get_state(World)
    :ok
  end

  defp start_server(pose) do
    config = Keyword.merge([type: :ld6001a], pose)
    start_supervised!({Server, [device_id: :erlang.unique_integer([:positive]), config: config, mode: :exact]}, id: {:server, pose})
  end

  # Collect bytes for the given port until a complete frame with at least one
  # track is parsed. AT+OK acks and partial reads are tolerated.
  defp await_frame(port), do: await_frame(port, <<>>, deadline_ms(2_000))

  defp await_frame(port, buffer, deadline) do
    timeout = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {:circuits_uart, ^port, bytes} ->
        case Protocol.feed(buffer, bytes) do
          {[%Frame{tracks: [_ | _]} = frame | _], _errors, _leftover} ->
            frame

          {_frames, _errors, leftover} ->
            await_frame(port, leftover, deadline)
        end
    after
      timeout -> flunk("no frame with tracks received on #{port} within deadline")
    end
  end

  defp deadline_ms(ms), do: System.monotonic_time(:millisecond) + ms
end
