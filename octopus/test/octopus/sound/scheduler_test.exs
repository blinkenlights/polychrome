defmodule Octopus.Sound.SchedulerTest do
  # Not async: the engine is picked from application config.
  use ExUnit.Case, async: false

  alias Octopus.Sound.{Clock, Engine, Scheduler, Time}

  setup do
    previous = Application.get_env(:octopus, Octopus.Sound, [])

    Application.put_env(
      :octopus,
      Octopus.Sound,
      Keyword.merge(previous, engine: Engine.Recorder, lookahead_ms: 200)
    )

    Engine.Recorder.attach()

    on_exit(fn ->
      Engine.Recorder.detach()
      Application.put_env(:octopus, Octopus.Sound, previous)
    end)

    start_supervised!({Clock, bpm: 240.0, loop_bars: 2})
    start_supervised!({Scheduler, lookahead_ms: 200})

    :ok
  end

  test "emits nothing while the transport is stopped" do
    Scheduler.metronome(true)

    refute_receive {:note, _}, 150
  end

  test "emits one metronome note per beat, ahead of time" do
    Scheduler.metronome(true)
    Clock.play()

    # 240 bpm is four beats per second, so a beat lands every 250 ms.
    assert_receive {:note, first}, 500
    assert first.channel == 1
    assert first.synth == "pc_click"

    assert_receive {:note, second}, 500

    # The point of the look-ahead: a note is handed to the engine long before
    # it sounds. Measured here right after it arrives.
    lead_ms = second.at_ms - Time.now()
    assert lead_ms > 100, "expected the note to be scheduled ahead, lead was #{lead_ms} ms"
    assert lead_ms <= 250

    assert_in_delta second.at_ms - first.at_ms, 250, 30
  end

  test "accents the first beat of the bar" do
    Scheduler.metronome(true)
    Clock.seek(0)
    Clock.play()

    notes =
      for _ <- 1..4 do
        assert_receive {:note, note}, 800
        note
      end

    assert Enum.any?(notes, &(&1.velocity == 0.9))
    assert Enum.any?(notes, &(&1.velocity == 0.5))
  end

  test "a custom source decides what sounds" do
    Scheduler.set_source(fn step, _timeline ->
      if rem(step.index, 4) == 0, do: [%{channel: 7, note: 60, synth: "pc_ping"}], else: []
    end)

    Clock.play()

    assert_receive {:note, %{channel: 7, synth: "pc_ping"}}, 800
  end

  test "silence when no source is set" do
    Scheduler.set_source(nil)
    Clock.play()

    refute_receive {:note, _}, 200
  end
end
