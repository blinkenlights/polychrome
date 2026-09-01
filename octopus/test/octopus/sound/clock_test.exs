defmodule Octopus.Sound.ClockTest do
  use ExUnit.Case, async: true

  alias Octopus.Sound.Clock

  setup do
    start_supervised!({Clock, bpm: 120.0, loop_bars: 2})
    :ok
  end

  test "starts stopped at the beginning" do
    position = Clock.position()

    assert %{bar: 1, beat: 1, step: 1, playing?: false} = position
    assert position.beats == 0.0
  end

  test "advances while playing and holds when stopped" do
    Clock.play()
    Process.sleep(120)
    Clock.stop()

    stopped = Clock.position()
    assert stopped.beats > 0.0
    refute stopped.playing?

    Process.sleep(60)
    assert Clock.position().beats == stopped.beats
  end

  test "changing tempo does not move the playhead" do
    Clock.play()
    Process.sleep(60)

    before = Clock.position().beats
    after_change = Clock.set_bpm(60).beats

    assert_in_delta after_change, before, 0.05
    assert Clock.timeline().bpm == 60.0
  end

  test "seek jumps to an absolute beat" do
    position = Clock.seek(6)

    assert %{bar: 2, beat: 3} = position
    assert position.beats == 6.0
  end

  test "broadcasts the position while playing" do
    Clock.subscribe()
    Clock.play()

    assert_receive {:sound_clock, %{playing?: true, beats: beats}}, 500
    assert is_float(beats)
  end
end
