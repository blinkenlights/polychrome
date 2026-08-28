defmodule Octopus.InstallationTransportTest do
  use ExUnit.Case, async: false

  alias Octopus.{AppManager, AppSupervisor, InstallationTransport}
  alias Octopus.Apps.{CanvasTest, Collective, Matrix, Ocean, PerlinNoise, PixelFun, PixieDebug, Sand, SparkleMist, Wood}
  alias Octopus.Apps.PixelFun.Program

  @classic "pixelfun:classic_ripple"
  @cross "pixelfun:cross_waves"
  @matrix "matrix:matrix"
  @perlin "perlinnoise:perlin"
  @ocean "ocean:ocean"
  @sand "sand:sand"
  @sparkle_mist "sparklemist:mist"
  @dots "collective:dots"
  @classic_pf "pixelfun:classic_ripple"
  @marmor "pixelfun:marmor"

  setup do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Octopus.Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)

    if transport_pid = Process.whereis(Octopus.InstallationTransport) do
      Ecto.Adapters.SQL.Sandbox.allow(Octopus.Repo, self(), transport_pid)
    end

    for {_, app_id} <- AppSupervisor.running_apps(), do: AppSupervisor.stop_app(app_id)

    InstallationTransport.reset!()
    InstallationTransport.set_interval(300)
    InstallationTransport.set_transition_duration(0)

    on_exit(fn ->
      for {_, app_id} <- AppSupervisor.running_apps(), do: AppSupervisor.stop_app(app_id)
      InstallationTransport.reset!()
    end)

    :ok
  end

  defp state, do: InstallationTransport.get_state()

  defp pixel_fun_mode_count, do: length(Octopus.App.list_modes(PixelFun))

  defp with_matrix_installation(fun) do
    original = Application.get_env(:octopus, :installation)
    Application.put_env(:octopus, :installation, Octopus.Installation.Nation2026)

    try do
      fun.()
    after
      Application.put_env(:octopus, :installation, original)
    end
  end

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

  describe "set_transition_duration" do
    test "stores duration in public state" do
      InstallationTransport.set_transition_duration(2)
      assert state().transition_duration_seconds == 2.0
    end

    test "play_now with fade defers commit until black" do
      InstallationTransport.set_transition_duration(1)

      assert :ok = InstallationTransport.play_now(PixelFun, @classic_pf)

      s = state()
      assert s.pending_entry == %{app: PixelFun, mode_id: @classic_pf, mask: nil}
      assert s.live == nil or s.live.mode_id != @classic_pf
    end

    test "play_now with fade off commits immediately" do
      InstallationTransport.set_transition_duration(0)

      assert :ok = InstallationTransport.play_now(PixelFun, @classic_pf)

      s = state()
      assert s.pending_entry == nil
      assert s.live.mode_id == @classic_pf
    end
  end

  describe "next / prev" do
    test "next advances mixed queue" do
      InstallationTransport.set_queue([
        %{app: PixelFun, mode_id: @classic},
        %{app: Collective, mode_id: @dots}
      ])

      InstallationTransport.play_now(PixelFun, @classic)
      InstallationTransport.next()

      s = state()
      assert s.cycle_index == 1
      assert s.live.mode_id == @dots
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

  describe "single-item playlist" do
    test "empty queue has no countdown" do
      assert state().next_change_at_ms == nil
    end

    test "single queue entry runs countdown and restarts on next" do
      InstallationTransport.set_queue([%{app: PixelFun, mode_id: @classic}])
      InstallationTransport.play_now(PixelFun, @classic)

      assert is_integer(state().next_change_at_ms)

      InstallationTransport.next()
      assert state().cycle_index == 0
      assert state().live.mode_id == @classic
    end

    test "pause and resume work with a single queue entry" do
      InstallationTransport.set_queue([%{app: PixelFun, mode_id: @classic}])
      InstallationTransport.play_now(PixelFun, @classic)

      assert is_integer(state().next_change_at_ms)

      InstallationTransport.toggle_play()
      paused = state()
      assert paused.playing == false
      assert paused.next_change_at_ms == nil
      assert is_integer(paused.paused_remaining_ms)

      InstallationTransport.toggle_play()
      resumed = state()
      assert resumed.playing
      assert is_integer(resumed.next_change_at_ms)
    end

    test "restarts live queue entry when the running app stops" do
      InstallationTransport.set_queue([%{app: PixelFun, mode_id: @classic}])
      InstallationTransport.play_now(PixelFun, @classic)

      dead_id = state().now_playing.app_id
      assert AppManager.get_selected_app() == dead_id

      AppSupervisor.stop_app(dead_id)
      _ = :sys.get_state(InstallationTransport)

      s = state()
      assert s.live.mode_id == @classic
      assert is_binary(s.now_playing.app_id)
      assert s.now_playing.app_id != dead_id
      assert AppManager.get_selected_app() == s.now_playing.app_id
      assert is_integer(s.next_change_at_ms)
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

  describe "queue_add_all" do
    test "adds all presets for an app" do
      InstallationTransport.queue_add_all(PixelFun)

      s = state()
      assert length(s.queue) == pixel_fun_mode_count()
      assert Enum.all?(s.queue, &(&1.app == PixelFun))
    end

    test "skips presets already in the queue" do
      InstallationTransport.queue_toggle(PixelFun, @classic)
      InstallationTransport.queue_add_all(PixelFun)

      s = state()
      assert length(s.queue) == pixel_fun_mode_count()
      assert Enum.at(s.queue, 0).mode_id == @classic
    end

    test "no-op when all presets are already queued" do
      InstallationTransport.queue_add_all(PixelFun)
      count = length(state().queue)

      InstallationTransport.queue_add_all(PixelFun)

      assert length(state().queue) == count
    end

    test "starts first preset when queue was empty" do
      InstallationTransport.queue_add_all(PixelFun)

      s = state()
      assert s.live != nil
      assert s.live.mode_id == hd(Octopus.App.list_modes(PixelFun)).id
      assert s.cycle_index == 0
    end

    test "appends without changing live when queue already has entries" do
      with_matrix_installation(fn ->
        InstallationTransport.set_queue([%{app: Matrix, mode_id: @matrix}])
        InstallationTransport.play_now(Matrix, @matrix)

        InstallationTransport.queue_add_all(PixelFun)

        s = state()
        assert s.live.mode_id == @matrix
        assert length(s.queue) == 1 + pixel_fun_mode_count()
        assert Enum.at(s.queue, 0).mode_id == @matrix
      end)
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

    test "play_now while PixelFun is ticking switches mode" do
      assert :ok = InstallationTransport.play_now(PixelFun, @classic_pf)
      assert state().live.mode_id == @classic_pf

      Process.sleep(100)

      assert :ok = InstallationTransport.play_now(PixelFun, @marmor)

      s = state()
      assert s.live.app == PixelFun
      assert s.live.mode_id == @marmor
    end

    test "off-queue play pauses rotation so it stays on the wall" do
      with_matrix_installation(fn ->
        InstallationTransport.set_queue([
          %{app: PixelFun, mode_id: @classic},
          %{app: PixelFun, mode_id: @cross}
        ])

        InstallationTransport.play_now(Matrix, @matrix)

        s = state()
        assert s.live.app == Matrix
        assert s.live.mode_id == @matrix
        assert s.rotation_paused
        assert s.playing
        assert s.takeover_app_id != nil
        assert s.now_playing.effective[:speed] == 8.0
      end)
    end

    test "queue toggle starts first entry when nothing is live" do
      with_matrix_installation(fn ->
        assert InstallationTransport.get_state().live == nil

        InstallationTransport.queue_toggle(Matrix, @matrix)

        s = state()
        assert s.live.app == Matrix
        assert s.live.mode_id == @matrix
        assert length(s.queue) == 1
      end)
    end

    test "resume rotation snaps wall back to queue position after off-queue play" do
      with_matrix_installation(fn ->
        InstallationTransport.set_queue([
          %{app: PixelFun, mode_id: @classic},
          %{app: PixelFun, mode_id: @cross}
        ])

        InstallationTransport.play_now(PixelFun, @classic)
        InstallationTransport.play_now(Matrix, @matrix)

        assert state().live.app == Matrix
        assert state().rotation_paused
        assert state().cycle_index == 0

        InstallationTransport.resume_rotation_after_takeover()

        s = state()
        assert s.rotation_paused == false
        assert s.playing
        assert s.live.app == PixelFun
        assert s.live.mode_id == @classic
        assert s.cycle_index == 0
      end)
    end

    test "resume rotation restores queue after manual play_now takeover" do
      with_matrix_installation(fn ->
        InstallationTransport.set_queue([
          %{app: PixelFun, mode_id: @classic},
          %{app: PixelFun, mode_id: @cross}
        ])

        InstallationTransport.play_now(Matrix, @matrix)
        assert state().rotation_paused

        InstallationTransport.resume_rotation_after_takeover()

        s = state()
        assert s.rotation_paused == false
        assert s.playing
        assert s.live.app == PixelFun
        assert s.live.mode_id == @classic
      end)
    end

    test "resume rotation clears wall when queue is empty" do
      InstallationTransport.play_now(PixelFun, @classic)

      assert state().rotation_paused
      assert state().live.mode_id == @classic

      InstallationTransport.resume_rotation_after_takeover()

      s = state()
      assert s.rotation_paused == false
      assert s.live == nil
      assert AppManager.get_selected_app() == nil
    end
  end

  describe "launch_app" do
    test "pauses rotation and clears live entry for legacy apps" do
      InstallationTransport.set_queue([
        %{app: PixelFun, mode_id: @classic},
        %{app: PixelFun, mode_id: @cross}
      ])

      InstallationTransport.play_now(PixelFun, @classic)

      InstallationTransport.launch_app(CanvasTest)

      s = state()
      assert s.rotation_paused
      assert s.takeover_app_id != nil
      assert s.takeover_app_name == "Canvas Test"
      assert s.live == nil
      assert AppManager.get_selected_app() == s.takeover_app_id

      InstallationTransport.resume_rotation_after_takeover()

      s = state()
      assert s.rotation_paused == false
      assert s.live.app == PixelFun
      assert s.live.mode_id == @classic
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
      assert resumed.live.app == PixelFun
      assert resumed.live.mode_id == @classic
      assert resumed.cycle_index == 0
    end
  end

  describe "now_playing" do
    test "tweak applies live and marks dirty without changing stored mode" do
      InstallationTransport.play_now(PixelFun, @classic)

      before = state().now_playing
      assert before.dirty == false
      stored_drift = before.stored[:translate_scale_x]

      InstallationTransport.set_tweakable(:translate_scale_x, 4.0)

      tweaked = state().now_playing
      assert tweaked.dirty == true
      assert tweaked.stored[:translate_scale_x] == stored_drift
      assert tweaked.effective[:translate_scale_x] == 4.0

      {:ok, app_id} = AppSupervisor.find_running_app(PixelFun)
      assert AppSupervisor.config(app_id)[:translate_scale_x] == 4.0
    end

    test "discard restores stored values" do
      InstallationTransport.play_now(PixelFun, @classic)
      stored = state().now_playing.stored[:translate_scale_x]

      InstallationTransport.set_tweakable(:translate_scale_x, 4.0)
      InstallationTransport.discard_now_playing_overrides()

      after_discard = state().now_playing
      assert after_discard.dirty == false
      assert after_discard.effective[:translate_scale_x] == stored

      {:ok, app_id} = AppSupervisor.find_running_app(PixelFun)
      assert AppSupervisor.config(app_id)[:translate_scale_x] == stored
    end

    test "queue advance drops overrides" do
      InstallationTransport.set_queue([
        %{app: PixelFun, mode_id: @classic},
        %{app: PixelFun, mode_id: @cross}
      ])

      InstallationTransport.play_now(PixelFun, @classic)
      InstallationTransport.set_tweakable(:translate_scale_x, 4.0)
      InstallationTransport.next()

      advanced = state().now_playing
      assert advanced.mode_id == @cross
      assert advanced.dirty == false
      assert advanced.overrides == %{}
    end

    test "wood tweak keeps running config and applies speed live" do
      original_installation = Application.get_env(:octopus, :installation)
      Application.put_env(:octopus, :installation, Octopus.Installation.RunningLights)

      on_exit(fn ->
        Application.put_env(:octopus, :installation, original_installation)
      end)

      {:ok, app_id} =
        AppSupervisor.start_app(Wood, config: %{mode: :endless_up, speed: 2.0, blob_size: 3})

      InstallationTransport.play_now(Wood, "experiment")

      playing = state().now_playing
      assert playing.stored[:speed] == 2.0
      assert playing.stored[:blob_size] == 3
      assert playing.effective[:speed] == 2.0

      InstallationTransport.set_tweakable(:speed, 3.5)

      tweaked = state().now_playing
      assert tweaked.dirty == true
      assert tweaked.effective[:speed] == 3.5

      config = AppSupervisor.config(app_id)
      assert config[:speed] == 3.5
      assert config[:mode] == :endless_up
      assert config[:blob_size] == 3
    end

    test "pixie debug tweak applies layout_index live" do
      original_installation = Application.get_env(:octopus, :installation)
      Application.put_env(:octopus, :installation, Octopus.Installation.Pixie)

      on_exit(fn ->
        Application.put_env(:octopus, :installation, original_installation)
      end)

      InstallationTransport.play_now(PixieDebug, "pixel_walk")

      before = state().now_playing
      assert before.effective[:layout_index] == 0
      assert before.meta != []

      InstallationTransport.set_tweakable(:layout_index, 42)

      tweaked = state().now_playing
      assert tweaked.dirty == true
      assert tweaked.effective[:layout_index] == 42
      assert Enum.any?(tweaked.meta, &String.contains?(&1, "Layout"))

      {:ok, app_id} = AppSupervisor.find_running_app(PixieDebug)
      assert AppSupervisor.config(app_id)[:layout_index] == 42
    end

    test "pixie debug full panel tweak applies color live" do
      original_installation = Application.get_env(:octopus, :installation)
      Application.put_env(:octopus, :installation, Octopus.Installation.Pixie)

      on_exit(fn ->
        Application.put_env(:octopus, :installation, original_installation)
      end)

      InstallationTransport.play_now(PixieDebug, "full_panel")

      playing = state().now_playing
      assert playing.effective[:mode_id] == "full_panel"
      assert playing.effective[:color_channel] == :white
      assert playing.meta == ["Panel fill · white"]

      InstallationTransport.set_tweakable(:color_channel, :rgb)
      InstallationTransport.set_tweakable(:color, "#00ff00")

      tweaked = state().now_playing
      assert tweaked.effective[:color_channel] == :rgb
      assert tweaked.effective[:color] == "#00ff00"
      assert tweaked.meta == ["Panel fill · #00ff00 (RGB)"]

      {:ok, app_id} = AppSupervisor.find_running_app(PixieDebug)
      config = AppSupervisor.config(app_id)
      assert config[:color_channel] == :rgb
      assert config[:color] == "#00ff00"
    end

    test "pixie debug fade step tweak applies frame_index live" do
      original_installation = Application.get_env(:octopus, :installation)
      Application.put_env(:octopus, :installation, Octopus.Installation.Pixie)

      on_exit(fn ->
        Application.put_env(:octopus, :installation, original_installation)
      end)

      InstallationTransport.play_now(PixieDebug, "fade_step")

      playing = state().now_playing
      assert playing.effective[:mode_id] == "fade_step"
      assert playing.effective[:frame_index] == 0
      assert Enum.any?(playing.meta, &String.contains?(&1, "Frame 0"))

      InstallationTransport.set_tweakable(:frame_index, 15)

      tweaked = state().now_playing
      assert tweaked.dirty == true
      assert tweaked.effective[:frame_index] == 15
      assert Enum.any?(tweaked.meta, &String.contains?(&1, "Frame 15"))

      {:ok, app_id} = AppSupervisor.find_running_app(PixieDebug)
      assert AppSupervisor.config(app_id)[:frame_index] == 15
    end

    test "pixie debug fade loop tweak applies fade_half_duration_ms live" do
      original_installation = Application.get_env(:octopus, :installation)
      Application.put_env(:octopus, :installation, Octopus.Installation.Pixie)

      on_exit(fn ->
        Application.put_env(:octopus, :installation, original_installation)
      end)

      InstallationTransport.play_now(PixieDebug, "fade_loop")

      playing = state().now_playing
      assert playing.effective[:mode_id] == "fade_loop"
      assert playing.effective[:fade_half_duration_ms] == 3000

      InstallationTransport.set_tweakable(:fade_half_duration_ms, 5000)

      tweaked = state().now_playing
      assert tweaked.dirty == true
      assert tweaked.effective[:fade_half_duration_ms] == 5000

      {:ok, app_id} = AppSupervisor.find_running_app(PixieDebug)
      assert AppSupervisor.config(app_id)[:fade_half_duration_ms] == 5000
    end

    test "collective storm tweak applies sensitivity live" do
      InstallationTransport.play_now(Collective, "collective:storm")

      playing = state().now_playing
      assert playing.effective[:animation] == :storm
      assert playing.effective[:sensitivity] == 1.0
      assert length(playing.tweakables) == 4
      assert playing.meta != []

      InstallationTransport.set_tweakable(:sensitivity, 2.0)

      tweaked = state().now_playing
      assert tweaked.dirty == true
      assert tweaked.effective[:sensitivity] == 2.0

      {:ok, app_id} = AppSupervisor.find_running_app(Collective)
      assert AppSupervisor.config(app_id)[:sensitivity] == 2.0
    end

    test "collective lava lamp tweak applies palette live" do
      InstallationTransport.play_now(Collective, "collective:lava_lamp")

      playing = state().now_playing
      assert playing.effective[:animation] == :lava_lamp
      assert playing.effective[:lava_palette] == :classic

      InstallationTransport.set_tweakable(:lava_palette, :magenta)

      tweaked = state().now_playing
      assert tweaked.dirty == true
      assert tweaked.effective[:lava_palette] == :magenta

      {:ok, app_id} = AppSupervisor.find_running_app(Collective)
      assert AppSupervisor.config(app_id)[:lava_palette] == :magenta
    end

    test "matrix tweak applies speed and density live" do
      with_matrix_installation(fn ->
        InstallationTransport.play_now(Matrix, @matrix)

        playing = state().now_playing
        assert playing.effective[:speed] == 8.0
        assert playing.effective[:density] == 1
        assert playing.effective[:max_particles] == 24
        assert length(playing.tweakables) == length(Matrix.mode_tweakables(@matrix))
        assert "24 particles max" in playing.meta
        assert "density 1" in playing.meta

        InstallationTransport.set_tweakable(:speed, 2.0)
        InstallationTransport.set_tweakable(:density, 6)

        tweaked = state().now_playing
        assert tweaked.dirty == true
        assert tweaked.effective[:speed] == 2.0
        assert tweaked.effective[:density] == 6

        {:ok, app_id} = AppSupervisor.find_running_app(Matrix)
        config = AppSupervisor.config(app_id)
        assert config[:speed] == 2.0
        assert config[:density] == 6
      end)
    end
  end

  describe "live tweaks" do
    test "collective tweak marks dirty without persisting preset" do
      InstallationTransport.play_now(Collective, "collective:storm")
      InstallationTransport.set_tweakable(:sensitivity, 2.5)

      assert state().now_playing.dirty == true
      assert state().now_playing.effective[:sensitivity] == 2.5
      assert state().now_playing.has_presets
    end

    test "matrix now playing exposes preset library flag" do
      with_matrix_installation(fn ->
        InstallationTransport.play_now(Matrix, @matrix)

        np = state().now_playing
        assert np.has_presets
        refute Map.has_key?(np, :overwriteable)
        refute Map.has_key?(np, :deletable)
        refute Map.has_key?(np, :renamable)
      end)
    end

    test "pixel fun exposes formula tweakable" do
      InstallationTransport.play_now(PixelFun, @classic)

      playing = state().now_playing
      assert length(playing.tweakables) == length(PixelFun.mode_tweakables(@classic))
      assert Enum.any?(playing.tweakables, &(&1.key == :program and &1.type == :formula))
      assert playing.effective[:program] == "sin(0.4*t-hypot(x,y))"
    end

    test "pixel fun formula tweak applies live and marks dirty" do
      InstallationTransport.play_now(PixelFun, @classic)

      stored_formula = state().now_playing.stored[:program]
      InstallationTransport.set_tweakable(:program, "sin(x+t)")

      tweaked = state().now_playing
      assert tweaked.dirty == true
      assert tweaked.stored[:program] == stored_formula
      assert tweaked.effective[:program] == "sin(x+t)"

      {:ok, app_id} = AppSupervisor.find_running_app(PixelFun)
      assert AppSupervisor.config(app_id)[:program] == "sin(x+t)"
    end

    test "pixel fun invalid formula keeps last valid program on the wall" do
      {:ok, original_ast} = Program.parse("sin(0.4*t-hypot(x,y))")

      InstallationTransport.play_now(PixelFun, @classic)
      InstallationTransport.set_tweakable(:program, "sin(+")

      tweaked = state().now_playing
      assert tweaked.dirty == true
      assert tweaked.effective[:program] == "sin(+"

      {:ok, app_id} = AppSupervisor.find_running_app(PixelFun)
      {pid, _} = AppSupervisor.lookup_app(app_id)
      %{program: program_ast} = :sys.get_state(pid)
      assert program_ast == original_ast
    end

    test "tweak recovers when now_playing_app_id is stale" do
      InstallationTransport.play_now(PixelFun, @classic)
      stale_id = state().now_playing.app_id
      AppSupervisor.stop_app(stale_id)

      InstallationTransport.set_tweakable(:zoom_base, 3.5)

      s = state().now_playing
      assert s.effective[:zoom_base] == 3.5
      assert is_binary(s.app_id)
      assert s.app_id != stale_id

      {:ok, app_id} = AppSupervisor.find_running_app(PixelFun)
      assert app_id == s.app_id
      assert AppSupervisor.config(app_id)[:zoom_base] == 3.5
    end

    test "perlin noise tweak applies scale and speed live" do
      InstallationTransport.play_now(PerlinNoise, @perlin)

      playing = state().now_playing
      assert playing.effective[:scale] == PerlinNoise.default_scale()
      assert playing.effective[:octaves] == 4
      assert playing.effective[:speed] == 1.0
      assert playing.effective[:seed] == 42
      assert playing.effective[:contrast] == 3.0
      assert length(playing.tweakables) == 4
      assert playing.has_presets

      InstallationTransport.set_tweakable(:scale, 0.25)
      InstallationTransport.set_tweakable(:speed, 2.0)
      InstallationTransport.set_tweakable(:contrast, 5.0)

      tweaked = state().now_playing
      assert tweaked.dirty == true
      assert tweaked.effective[:scale] == 0.25
      assert tweaked.effective[:speed] == 2.0
      assert tweaked.effective[:contrast] == 5.0

      {:ok, app_id} = AppSupervisor.find_running_app(PerlinNoise)
      config = AppSupervisor.config(app_id)
      assert config[:scale] == 0.25
      assert config[:speed] == 2.0
      assert config[:contrast] == 5.0
    end

    test "ocean tweak applies wave_strength and water_level live" do
      InstallationTransport.play_now(Ocean, @ocean)

      playing = state().now_playing
      assert playing.effective[:wave_strength] == 1.0
      assert playing.effective[:damping] == 0.95
      assert playing.effective[:water_level] == 0.6
      assert length(playing.tweakables) == 3
      assert playing.has_presets

      InstallationTransport.set_tweakable(:wave_strength, 2.0)
      InstallationTransport.set_tweakable(:water_level, 0.75)

      tweaked = state().now_playing
      assert tweaked.dirty == true
      assert tweaked.effective[:wave_strength] == 2.0
      assert tweaked.effective[:water_level] == 0.75

      {:ok, app_id} = AppSupervisor.find_running_app(Ocean)
      config = AppSupervisor.config(app_id)
      assert config[:wave_strength] == 2.0
      assert config[:water_level] == 0.75
    end

    test "sand tweak applies spawn_rate and button_force live" do
      InstallationTransport.play_now(Sand, @sand)

      playing = state().now_playing
      assert playing.effective[:spawn_rate] == 0.25
      assert playing.effective[:button_force] == 40
      assert playing.effective[:auto_drain] == true
      assert playing.effective[:color_mode] == :rainbow
      assert length(playing.tweakables) == length(Sand.mode_tweakables(@sand))
      assert playing.has_presets

      InstallationTransport.set_tweakable(:spawn_rate, 0.5)
      InstallationTransport.set_tweakable(:color_mode, :warm)

      tweaked = state().now_playing
      assert tweaked.dirty == true
      assert tweaked.effective[:spawn_rate] == 0.5
      assert tweaked.effective[:color_mode] == :warm

      {:ok, app_id} = AppSupervisor.find_running_app(Sand)
      config = AppSupervisor.config(app_id)
      assert config[:spawn_rate] == 0.5
      assert config[:color_mode] == :warm
    end

    test "sparkle mist tweak applies foreground_hue and background_speed live" do
      InstallationTransport.play_now(SparkleMist, @sparkle_mist)

      playing = state().now_playing
      assert playing.effective[:foreground_hue] == 25
      assert playing.effective[:background_speed] == 5.0
      assert playing.effective[:particle_speed_scale] == 1.0
      assert playing.effective[:background_hue_a] == 200
      assert length(playing.tweakables) == 4
      assert playing.has_presets

      InstallationTransport.set_tweakable(:foreground_hue, 140)
      InstallationTransport.set_tweakable(:background_speed, 3.5)

      tweaked = state().now_playing
      assert tweaked.dirty == true
      assert tweaked.effective[:foreground_hue] == 140
      assert tweaked.effective[:background_speed] == 3.5

      {:ok, app_id} = AppSupervisor.find_running_app(SparkleMist)
      config = AppSupervisor.config(app_id)
      assert config[:foreground_hue] == 140
      assert config[:background_speed] == 3.5
    end
  end

  describe "per-track masks" do
    test "play_now without mask keeps mask slot empty" do
      InstallationTransport.set_queue([
        %{app: PixelFun, mode_id: @classic, mask: nil}
      ])

      :ok = InstallationTransport.play_now(PixelFun, @classic)
      _ = :sys.get_state(InstallationTransport)

      assert AppManager.get_mask_app() == nil
    end

    test "queue entry with mask starts mask app" do
      InstallationTransport.set_queue([
        %{app: PixelFun, mode_id: @classic, mask: %{app: PerlinNoise, mode_id: @perlin}}
      ])

      :ok = InstallationTransport.play_now(PixelFun, @classic)
      _ = :sys.get_state(InstallationTransport)

      assert AppManager.get_mask_app() != nil
      assert {:ok, _} = AppSupervisor.find_running_app(PerlinNoise)
    end

    test "switching to track without mask stops mask" do
      InstallationTransport.set_queue([
        %{app: PixelFun, mode_id: @classic, mask: %{app: PerlinNoise, mode_id: @perlin}},
        %{app: PixelFun, mode_id: @cross, mask: nil}
      ])

      :ok = InstallationTransport.play_now(PixelFun, @classic)
      _ = :sys.get_state(InstallationTransport)
      assert AppManager.get_mask_app() != nil

      InstallationTransport.next()
      _ = :sys.get_state(InstallationTransport)

      assert AppManager.get_mask_app() == nil
      assert state().live.mode_id == @cross
    end

    test "queue_set_mask updates mask on live track" do
      InstallationTransport.set_queue([
        %{app: PixelFun, mode_id: @classic, mask: nil}
      ])

      :ok = InstallationTransport.play_now(PixelFun, @classic)
      _ = :sys.get_state(InstallationTransport)
      assert AppManager.get_mask_app() == nil

      :ok = InstallationTransport.queue_set_mask(0, %{app: PerlinNoise, mode_id: @perlin})
      _ = :sys.get_state(InstallationTransport)

      assert AppManager.get_mask_app() != nil
      assert {:ok, _} = AppSupervisor.find_running_app(PerlinNoise)
    end
  end

  describe "restore_playback" do
    test "restore_queue_playback starts the clamped queue entry" do
      state = base_restore_state([
        %{app: PixelFun, mode_id: @classic},
        %{app: PixelFun, mode_id: @cross}
      ])

      restored = InstallationTransport.restore_queue_playback(state)

      assert restored.playing
      assert restored.cycle_index == 1
      assert restored.live_entry.mode_id == @cross
      assert is_binary(restored.now_playing_app_id)
      assert is_integer(restored.next_change_at_ms)
    end

    test "restore_queue_playback auto-resumes when playing was false" do
      state =
        base_restore_state([%{app: PixelFun, mode_id: @classic}])
        |> Map.put(:playing, false)

      restored = InstallationTransport.restore_queue_playback(state)

      assert restored.live_entry.mode_id == @classic
      assert is_integer(restored.next_change_at_ms)
    end

    test "restore_queue_playback clamps out-of-bounds cycle_index" do
      state =
        base_restore_state([
          %{app: PixelFun, mode_id: @classic},
          %{app: PixelFun, mode_id: @cross}
        ])
        |> Map.put(:cycle_index, 99)

      restored = InstallationTransport.restore_queue_playback(state)

      assert restored.cycle_index == 1
      assert restored.live_entry.mode_id == @cross
      assert is_integer(restored.next_change_at_ms)
    end
  end

  defp base_restore_state(entries) do
    queue = Enum.map(entries, &normalize_restore_entry/1)

    %InstallationTransport.State{
      queue: queue,
      cycle_interval_seconds: 300.0,
      transition_duration_seconds: 0.0,
      cycle_index: length(queue) - 1,
      cycle_timer_ref: nil,
      playing: true,
      paused_remaining_ms: nil,
      next_change_at_ms: nil,
      live_entry: nil,
      pending_entry: nil,
      rotation_paused: false,
      takeover_app_id: nil,
      now_playing_stored_config: %{},
      now_playing_overrides: %{},
      now_playing_app_id: nil
    }
  end

  defp normalize_restore_entry(%{app: app, mode_id: mode_id}) do
    app =
      if is_atom(app) and function_exported?(app, :list_modes, 0) do
        app
      else
        Module.concat(Octopus.Apps, app)
      end

    %{app: app, mode_id: to_string(mode_id), mask: nil}
  end
end
