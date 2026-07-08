defmodule Octopus.InstallationTransportTest do
  use ExUnit.Case, async: false

  alias Octopus.{AppSupervisor, InstallationTransport}
  alias Octopus.Apps.{Collective, PixelFun}

  @classic "builtin:classic_ripple"
  @cross "builtin:cross_waves"

  setup do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Octopus.Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)

    if transport_pid = Process.whereis(Octopus.InstallationTransport) do
      Ecto.Adapters.SQL.Sandbox.allow(Octopus.Repo, self(), transport_pid)
    end

    for {_, app_id} <- AppSupervisor.running_apps(), do: AppSupervisor.stop_app(app_id)

    InstallationTransport.set_queue([])
    InstallationTransport.set_interval(300)
    InstallationTransport.resume_rotation_after_takeover()

    on_exit(fn ->
      for {_, app_id} <- AppSupervisor.running_apps(), do: AppSupervisor.stop_app(app_id)
      InstallationTransport.set_queue([])
      InstallationTransport.resume_rotation_after_takeover()
    end)

    :ok
  end

  defp state, do: InstallationTransport.get_state()

  describe "toggle_play" do
    test "pause freezes remaining time" do
      InstallationTransport.set_queue([
        %{app: PixelFun, mode_id: @classic},
        %{app: PixelFun, mode_id: @cross}
      ])

      InstallationTransport.play_now(PixelFun, @classic)

      before = state()
      assert before.playing
      assert is_integer(before.next_change_at_ms)

      Process.sleep(50)
      InstallationTransport.toggle_play()
      paused = state()

      assert paused.playing == false
      assert paused.next_change_at_ms == nil
      assert is_integer(paused.paused_remaining_ms)
      assert paused.paused_remaining_ms > 0
    end

    test "resume reschedules from frozen remainder" do
      InstallationTransport.set_queue([
        %{app: PixelFun, mode_id: @classic},
        %{app: PixelFun, mode_id: @cross}
      ])

      InstallationTransport.play_now(PixelFun, @classic)
      InstallationTransport.toggle_play()

      remaining = state().paused_remaining_ms
      InstallationTransport.toggle_play()
      resumed = state()

      assert resumed.playing
      assert resumed.paused_remaining_ms == nil
      assert is_integer(resumed.next_change_at_ms)
      assert_in_delta resumed.next_change_at_ms - System.os_time(:millisecond), remaining, 2_000
    end
  end

  describe "set_interval" do
    test "does not reset running countdown" do
      InstallationTransport.set_queue([
        %{app: PixelFun, mode_id: @classic},
        %{app: PixelFun, mode_id: @cross}
      ])

      InstallationTransport.play_now(PixelFun, @classic)
      deadline = state().next_change_at_ms

      InstallationTransport.set_interval(30)
      updated = state()

      assert updated.cycle_interval_seconds == 30.0
      assert updated.next_change_at_ms == deadline
    end
  end

  describe "next / prev" do
    test "next advances mixed queue" do
      InstallationTransport.set_queue([
        %{app: PixelFun, mode_id: @classic},
        %{app: Collective, mode_id: "orbital"}
      ])

      InstallationTransport.play_now(PixelFun, @classic)
      InstallationTransport.next()

      s = state()
      assert s.cycle_index == 1
      assert s.live.mode_id == "orbital"
      assert s.live.app == Collective
    end

    test "prev wraps" do
      InstallationTransport.set_queue([
        %{app: PixelFun, mode_id: @classic},
        %{app: PixelFun, mode_id: @cross}
      ])

      InstallationTransport.play_now(PixelFun, @classic)
      InstallationTransport.prev()

      assert state().cycle_index == 1
      assert state().live.mode_id == @cross
    end
  end

  describe "holding" do
    test "no countdown with 0 or 1 queued" do
      InstallationTransport.set_queue([%{app: PixelFun, mode_id: @classic}])
      InstallationTransport.play_now(PixelFun, @classic)

      assert state().next_change_at_ms == nil

      InstallationTransport.next()
      assert state().cycle_index == 0
    end

    test "second queue entry starts countdown" do
      InstallationTransport.set_queue([%{app: PixelFun, mode_id: @classic}])
      InstallationTransport.play_now(PixelFun, @classic)

      InstallationTransport.queue_toggle(PixelFun, @cross)

      assert is_integer(state().next_change_at_ms)
    end
  end

  describe "queue_toggle" do
    test "adds and removes entries" do
      InstallationTransport.queue_toggle(PixelFun, @classic)
      assert length(state().queue) == 1

      InstallationTransport.queue_toggle(PixelFun, @classic)
      assert state().queue == []
    end
  end

  describe "queue_move" do
    test "reorders with up/down" do
      InstallationTransport.set_queue([
        %{app: PixelFun, mode_id: @classic},
        %{app: PixelFun, mode_id: @cross}
      ])

      InstallationTransport.queue_move(1, "up")
      assert Enum.at(state().queue, 0).mode_id == @cross

      InstallationTransport.queue_move(0, "down")
      assert Enum.at(state().queue, 0).mode_id == @classic
    end

    test "keeps cycle_index on the live entry after reorder" do
      InstallationTransport.set_queue([
        %{app: PixelFun, mode_id: @classic},
        %{app: PixelFun, mode_id: @cross}
      ])

      InstallationTransport.play_now(PixelFun, @classic)
      assert state().cycle_index == 0

      InstallationTransport.queue_move(0, "down")

      s = state()
      assert s.cycle_index == 1
      assert s.live.mode_id == @classic
      assert Enum.at(s.queue, rem(s.cycle_index + 1, 2)).mode_id == @cross
    end
  end

  describe "play_now" do
    test "jumps queue index when entry is queued" do
      InstallationTransport.set_queue([
        %{app: PixelFun, mode_id: @classic},
        %{app: PixelFun, mode_id: @cross}
      ])

      InstallationTransport.play_now(PixelFun, @cross)
      assert state().cycle_index == 1
      assert state().live.mode_id == @cross
    end
  end

  describe "rotation_paused" do
    test "takeover pauses rotation and resume restores it" do
      InstallationTransport.set_queue([
        %{app: PixelFun, mode_id: @classic},
        %{app: PixelFun, mode_id: @cross}
      ])

      InstallationTransport.play_now(PixelFun, @classic)
      InstallationTransport.pause_rotation_for_takeover("game-test-id")

      paused = state()
      assert paused.rotation_paused
      assert paused.takeover_app_id == "game-test-id"
      assert paused.playing == false

      InstallationTransport.resume_rotation_after_takeover()
      resumed = state()

      assert resumed.rotation_paused == false
      assert resumed.takeover_app_id == nil
      assert resumed.playing
    end
  end
end
