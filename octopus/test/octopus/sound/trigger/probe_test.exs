defmodule Octopus.Sound.Trigger.ProbeTest do
  use ExUnit.Case, async: false

  alias Octopus.Sound.{Engine, Patch, Pattern, Time}
  alias Octopus.Sound.Trigger.Probe

  describe "crossings on the value" do
    defp value_crossings(previous, current, min_rise) do
      {before, now} = measured(previous, current, :value)
      Probe.crossings(before, now, 0.0, min_rise)
    end

    test "reports panels whose value rose through zero, and how steeply" do
      assert [{0, rise}] = value_crossings([-0.5, 0.4, -0.9], [0.6, 0.7, -0.2], 0.01)
      assert_in_delta rise, 1.1, 1.0e-6
    end

    test "ignores falling edges — that is the same wave leaving" do
      assert value_crossings([0.6, 0.2], [-0.4, -0.1], 0.01) == []
    end

    test "a crossing is gated on steepness, not on height" do
      # At a crossing the quantity is by definition at the level, so a slow
      # wave barely moves between two frames and a fast one moves a lot.
      assert value_crossings([-0.001], [0.001], 0.01) == []
      assert [{0, _}] = value_crossings([-0.03], [0.03], 0.01)
    end

    test "treats an exact zero as below the crossing, not on it" do
      assert [{0, _}] = value_crossings([0.0], [0.9], 0.01)
      assert value_crossings([-0.9], [0.0], 0.01) == []
    end
  end

  describe "crossings on brightness" do
    # What the wall actually shows: the picture paints |value|, so both halves
    # of a wave are a visible band and both should sound.
    test "fires when the panel lights up, on either half of the wave" do
      assert [{0, _}] = brightness_crossings([0.3], [0.7])
      assert [{0, _}] = brightness_crossings([-0.3], [-0.7])
    end

    test "stays quiet while the panel is dark, however fast it moves there" do
      # The value races through zero, but the panel is black the whole time.
      assert brightness_crossings([-0.2], [0.2]) == []
    end

    test "does not fire again as the band leaves" do
      assert brightness_crossings([0.7], [0.3]) == []
    end

    defp brightness_crossings(previous, current) do
      {before, now} = measured(previous, current, :brightness)
      Probe.crossings(before, now, 0.55, 0.01)
    end
  end

  describe "crossings on speed" do
    # Speed is not a property of a frame but of the step between two, so it
    # only starts to say something on the third.
    test "says nothing until three frames have arrived" do
      assert Probe.series(%{previous: [], before_previous: []}, [0.1], 66, :speed) == {[], []}

      assert Probe.series(
               %{previous: [0.1], before_previous: [], before_previous_at: nil, previous_at: 33},
               [0.2],
               66,
               :speed
             ) == {[], []}
    end

    test "measures per second, so a level means the same at any frame rate" do
      # The same 0.3 step, seen once over 33 ms and once over 66 ms.
      {_before, [fast]} = speed([0.0], [0.0], [0.3], 33)
      {_before, [slow]} = speed([0.0], [0.0], [0.3], 66)

      assert_in_delta fast, 0.3 / 0.033, 0.1
      assert_in_delta slow, 0.3 / 0.066, 0.1
    end

    test "fires on the flank, not on a panel that sits still however bright" do
      # Held at full brightness: no movement, so no crossing.
      {before, now} = speed([0.9], [0.9], [0.9], 33)
      assert Probe.crossings(before, now, 1.0, 0.01) == []

      # The same panel racing from dark to bright.
      {before, now} = speed([0.0], [0.0], [0.9], 33)
      assert [{0, _}] = Probe.crossings(before, now, 1.0, 0.01)
    end

    test "does not care which way the picture moves — going dark is a flank too" do
      {before, now} = speed([0.9], [0.9], [0.0], 33)
      assert [{0, _}] = Probe.crossings(before, now, 1.0, 0.01)
    end

    defp speed(before_previous, previous, values, frame_ms) do
      Probe.series(
        %{
          before_previous: before_previous,
          before_previous_at: 0,
          previous: previous,
          previous_at: frame_ms
        },
        values,
        2 * frame_ms,
        :speed
      )
    end
  end

  defp measured(previous, current, quantity) do
    Probe.series(%{previous: previous}, current, 0, quantity)
  end

  describe "crossing_fraction/2" do
    test "says where between two frames the value passed zero" do
      assert Probe.crossing_fraction(-0.5, 0.5) == 0.5
      assert_in_delta Probe.crossing_fraction(-0.9, 0.1), 0.9, 1.0e-9
      assert Probe.crossing_fraction(0.0, 1.0) == 0.0
    end
  end

  describe "probe slots" do
    setup do
      previous = Application.get_env(:octopus, Octopus.Sound, [])

      Application.put_env(
        :octopus,
        Octopus.Sound,
        Keyword.merge(previous, engine: Engine.Recorder, channels: 12)
      )

      Engine.Recorder.attach()

      on_exit(fn ->
        Engine.Recorder.detach()
        Application.put_env(:octopus, Octopus.Sound, previous)
      end)

      start_supervised!(Patch)
      probe = start_supervised!({Probe, latency_ms: 0})
      # The tests below feed values directly, so they watch the value crossing
      # zero rather than brightness.
      Patch.update(&Pattern.as_chase(&1, 1, trigger: [quantity: :value, level: 0.0]))
      _ = :sys.get_state(probe)

      %{probe: probe}
    end

    test "stays silent on the first frame — there is nothing to compare to", %{probe: probe} do
      reading(probe, [0.8, 0.9, 0.7])

      refute_receive {:note, _}, 100
    end

    test "sounds the panel the wave is passing", %{probe: probe} do
      reading(probe, [-0.5, -0.4, -0.9])
      reading(probe, [-0.4, 0.8, -0.8])

      assert_receive {:note, note}, 200
      # Panel index 1 is channel 2: channels are 1-based and mean panels.
      assert note.channel == 2
      assert note.synth == "pc_ping"
      refute_receive {:note, _}, 50
    end

    test "a wave travelling around the ring sounds one panel after the other",
         %{probe: probe} do
      reading(probe, [-0.5, -0.5, -0.5, -0.5])
      reading(probe, [0.6, -0.5, -0.5, -0.5])
      reading(probe, [0.6, 0.6, -0.5, -0.5])
      reading(probe, [0.6, 0.6, 0.6, -0.5])

      channels =
        for _ <- 1..3 do
          assert_receive {:note, note}, 200
          note.channel
        end

      assert channels == [1, 2, 3]
    end

    test "each panel sounds its own pitch", %{probe: probe} do
      reading(probe, [-0.5, -0.5])
      reading(probe, [0.6, 0.6])

      assert_receive {:note, first}, 200
      assert_receive {:note, second}, 200
      refute first.note == second.note
    end

    test "two chases sound side by side — impossible before slots", %{probe: probe} do
      Patch.update(
        &Pattern.as_chase(&1, 2,
          synth: "pc_pluck",
          note: 38,
          trigger: [quantity: :value, level: 0.0]
        )
      )

      _ = :sys.get_state(probe)

      reading(probe, [-0.5])
      reading(probe, [0.6])

      synths =
        for _ <- 1..2 do
          assert_receive {:note, note}, 200
          note.synth
        end

      assert Enum.sort(synths) == ["pc_ping", "pc_pluck"]
    end

    test "the gate belongs to the slot, so two chases can differ", %{probe: probe} do
      Patch.update(
        &Pattern.configure_slot(&1, 2, %{
          synth: "pc_pluck",
          trigger: %{
            kind: :probe,
            quantity: :value,
            level: 0.0,
            min_rise: 0.9,
            min_interval_ms: 0
          },
          channel: %{mode: :follow_probe}
        })
      )

      _ = :sys.get_state(probe)

      reading(probe, [-0.02])
      reading(probe, [0.02])

      assert_receive {:note, %{synth: "pc_ping"}}, 200
      refute_receive {:note, %{synth: "pc_pluck"}}, 80
    end

    test "an even wave stays even, even when the frames do not arrive evenly",
         %{probe: probe} do
      Probe.set_latency(200)

      base = Time.now()
      arrivals = [0, 96, 207, 298, 411, 503, 592, 707, 803, 898, 1_010]

      Enum.each(arrivals, fn offset ->
        value = :math.sin(2 * :math.pi() * offset / 500)
        send(probe, {:pixel_probes, %{values: [value], seconds: 0.0, at_ms: base + offset}})
        _ = :sys.get_state(probe)
      end)

      notes =
        for _ <- 1..2 do
          assert_receive {:note, note}, 300
          note.at_ms
        end

      [first, second] = notes
      assert_in_delta second - first, 500, 12
    end

    test "a muted slot is silent", %{probe: probe} do
      Patch.update(&Pattern.toggle_mute(&1, 1))
      _ = :sys.get_state(probe)

      reading(probe, [-0.5])
      reading(probe, [0.6])

      refute_receive {:note, _}, 100
    end
  end

  defp reading(probe, values) do
    send(probe, {:pixel_probes, %{values: values, seconds: 0.0, at_ms: Time.now()}})
    _ = :sys.get_state(probe)
    :ok
  end
end
