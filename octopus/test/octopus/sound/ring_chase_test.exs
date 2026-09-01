defmodule Octopus.Sound.RingChaseTest do
  use ExUnit.Case, async: false

  alias Octopus.Sound.{Engine, RingChase, Time}

  describe "crossings/3" do
    test "reports panels whose value rose through zero, and how steeply" do
      assert [{0, rise}] = RingChase.crossings([-0.5, 0.4, -0.9], [0.6, 0.7, -0.2], 0.01)
      assert_in_delta rise, 1.1, 1.0e-6
    end

    test "ignores falling edges — that is the same wave leaving" do
      assert RingChase.crossings([0.6, 0.2], [-0.4, -0.1], 0.01) == []
    end

    test "a crossing is gated on steepness, not on height" do
      # The value at a crossing is always near zero; a slow wave barely moves
      # between two frames, a fast one moves a lot.
      assert RingChase.crossings([-0.001], [0.001], 0.01) == []
      assert [{0, _}] = RingChase.crossings([-0.03], [0.03], 0.01)
    end

    test "treats an exact zero as below the crossing, not on it" do
      assert [{0, _}] = RingChase.crossings([0.0], [0.9], 0.01)
      assert RingChase.crossings([-0.9], [0.0], 0.01) == []
    end
  end

  describe "the chase" do
    setup do
      previous = Application.get_env(:octopus, Octopus.Sound, [])

      Application.put_env(
        :octopus,
        Octopus.Sound,
        Keyword.put(previous, :engine, Engine.Recorder)
      )

      Engine.Recorder.attach()

      on_exit(fn ->
        Engine.Recorder.detach()
        Application.put_env(:octopus, Octopus.Sound, previous)
      end)

      pid = start_supervised!({RingChase, enabled: true, min_interval_ms: 0})
      %{chase: pid}
    end

    test "stays silent on the first frame — there is nothing to compare to", %{chase: chase} do
      probe(chase, [0.8, 0.9, 0.7])

      refute_receive {:note, _}, 100
    end

    test "sounds the panel the wave is passing", %{chase: chase} do
      probe(chase, [-0.5, -0.4, -0.9])
      probe(chase, [-0.4, 0.8, -0.8])

      assert_receive {:note, note}, 200
      # Panel index 1 is channel 2: channels are 1-based and mean panels.
      assert note.channel == 2
      assert note.synth == "pc_ping"
      refute_receive {:note, _}, 50
    end

    test "a wave travelling around the ring sounds one panel after the other",
         %{chase: chase} do
      probe(chase, [-0.5, -0.5, -0.5, -0.5])
      probe(chase, [0.6, -0.5, -0.5, -0.5])
      probe(chase, [0.6, 0.6, -0.5, -0.5])
      probe(chase, [0.6, 0.6, 0.6, -0.5])

      channels =
        for _ <- 1..3 do
          assert_receive {:note, note}, 200
          note.channel
        end

      assert channels == [1, 2, 3]
    end

    test "a steeper crossing is louder", %{chase: chase} do
      # Realistic frame-to-frame movement: a slow wave and a fast one.
      probe(chase, [-0.01, -0.06])
      probe(chase, [0.01, 0.06])

      assert_receive {:note, soft}, 200
      assert_receive {:note, loud}, 200

      assert loud.velocity > soft.velocity
    end

    test "holds back retriggers inside the minimum interval", %{chase: chase} do
      RingChase.configure(min_interval_ms: 10_000)

      probe(chase, [-0.5])
      probe(chase, [0.9])
      assert_receive {:note, _}, 200

      probe(chase, [-0.5])
      probe(chase, [0.9])
      refute_receive {:note, _}, 100
    end

    test "can be switched off", %{chase: chase} do
      RingChase.enable(false)

      probe(chase, [-0.5])
      probe(chase, [0.9])

      refute_receive {:note, _}, 100
    end
  end

  defp probe(chase, values) do
    send(chase, {:pixel_probes, %{values: values, seconds: 0.0, at_ms: Time.now()}})
    # Ensure the message is handled before the next frame is pushed in.
    _ = :sys.get_state(chase)
    :ok
  end
end
