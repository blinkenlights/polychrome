defmodule Octopus.InstallationTransportTest do
  use ExUnit.Case, async: false

  alias Octopus.{AppSupervisor, InstallationTransport}
  alias Octopus.Apps.{Collective, Matrix, Ocean, PerlinNoise, PixelFun, PixieDebug, Sand, SparkleMist, Wood}
  alias Octopus.Apps.PixelFun.Program

  @presets Module.concat(["Octopus", "AppModePresets"])

  @classic "pixelfun:classic_ripple"
  @cross "pixelfun:cross_waves"
  @matrix "matrix:matrix"
  @perlin "perlinnoise:perlin"
  @ocean "ocean:ocean"
  @sand "sand:sand"
  @sparkle_mist "sparklemist:mist"
  @orbital "collective:orbital"

  setup do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Octopus.Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)

    if transport_pid = Process.whereis(Octopus.InstallationTransport) do
      Ecto.Adapters.SQL.Sandbox.allow(Octopus.Repo, self(), transport_pid)
    end

    for {_, app_id} <- AppSupervisor.running_apps(), do: AppSupervisor.stop_app(app_id)

    InstallationTransport.reset!()
    InstallationTransport.set_interval(300)
    preset_sync_all!()

    on_exit(fn ->
      for {_, app_id} <- AppSupervisor.running_apps(), do: AppSupervisor.stop_app(app_id)
      InstallationTransport.reset!()
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
        %{app: Collective, mode_id: @orbital}
      ])

      InstallationTransport.play_now(PixelFun, @classic)
      InstallationTransport.next()

      s = state()
      assert s.cycle_index == 1
      assert s.live.mode_id == @orbital
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

    test "off-queue play pauses rotation so it stays on the wall" do
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
      assert s.now_playing.effective[:speed] == 1.0
    end

    test "queue toggle starts first entry when nothing is live" do
      assert InstallationTransport.get_state().live == nil

      InstallationTransport.queue_toggle(Matrix, @matrix)

      s = state()
      assert s.live.app == Matrix
      assert s.live.mode_id == @matrix
      assert length(s.queue) == 1
    end

    test "resume rotation snaps wall back to queue position after off-queue play" do
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
    end

    test "resume rotation restores queue after manual play_now takeover" do
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
      stored_drift = before.stored[:translate_scale]

      InstallationTransport.set_tweakable(:translate_scale, 4.0)

      tweaked = state().now_playing
      assert tweaked.dirty == true
      assert tweaked.stored[:translate_scale] == stored_drift
      assert tweaked.effective[:translate_scale] == 4.0

      {:ok, app_id} = AppSupervisor.find_running_app(PixelFun)
      assert AppSupervisor.config(app_id)[:translate_scale] == 4.0
    end

    test "discard restores stored values" do
      InstallationTransport.play_now(PixelFun, @classic)
      stored = state().now_playing.stored[:translate_scale]

      InstallationTransport.set_tweakable(:translate_scale, 4.0)
      InstallationTransport.discard_now_playing_overrides()

      after_discard = state().now_playing
      assert after_discard.dirty == false
      assert after_discard.effective[:translate_scale] == stored

      {:ok, app_id} = AppSupervisor.find_running_app(PixelFun)
      assert AppSupervisor.config(app_id)[:translate_scale] == stored
    end

    test "queue advance drops overrides" do
      InstallationTransport.set_queue([
        %{app: PixelFun, mode_id: @classic},
        %{app: PixelFun, mode_id: @cross}
      ])

      InstallationTransport.play_now(PixelFun, @classic)
      InstallationTransport.set_tweakable(:translate_scale, 4.0)
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

    test "collective storm tweak applies sensitivity live" do
      InstallationTransport.play_now(Collective, "collective:storm")

      playing = state().now_playing
      assert playing.effective[:animation] == :storm
      assert playing.effective[:sensitivity] == 1.0
      assert length(playing.tweakables) == 2
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
      InstallationTransport.play_now(Matrix, @matrix)

      playing = state().now_playing
      assert playing.effective[:speed] == 1.0
      assert playing.effective[:density] == 3
      assert playing.effective[:max_particles] == 200
      assert length(playing.tweakables) == 3
      assert playing.meta == ["200 particles max", "density 3"]

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
    end
  end

  describe "preset persistence" do
    test "save, overwrite, rename, and archive collective preset" do
      InstallationTransport.play_now(Collective, "collective:storm")
      InstallationTransport.set_tweakable(:sensitivity, 2.5)

      assert :ok = InstallationTransport.save_now_playing_as_new("Hot storm")
      assert state().now_playing.dirty == false

      user_modes =
        preset_list(Collective)
        |> Enum.filter(&(&1.origin == :user))

      assert Enum.any?(user_modes, &(&1.name == "Hot storm"))

      InstallationTransport.set_tweakable(:sensitivity, 3.0)
      assert :ok = InstallationTransport.overwrite_now_playing_mode()
      assert state().now_playing.effective[:sensitivity] == 3.0

      assert :ok = InstallationTransport.rename_now_playing_preset("Stormier")

      s = state()
      assert s.now_playing.preset_name == "Stormier"
      assert s.live.mode_name == "Stormier"

      InstallationTransport.set_queue([
        %{app: Collective, mode_id: "collective:storm"},
        %{app: Collective, mode_id: "collective:breath"}
      ])

      assert :ok = InstallationTransport.archive_now_playing_mode()

      queue = state().queue
      assert length(queue) == 1
      assert hd(queue).mode_id == "collective:breath"
    end

    test "save and overwrite matrix builtin" do
      InstallationTransport.play_now(Matrix, @matrix)
      InstallationTransport.set_tweakable(:speed, 2.5)

      np = state().now_playing
      assert np.persistable
      assert np.overwriteable
      assert np.deletable
      assert np.renamable

      assert :ok = InstallationTransport.overwrite_now_playing_mode()
      assert state().now_playing.effective[:speed] == 2.5
      assert state().now_playing.dirty == false

      preset = preset_get(Matrix, @matrix)
      assert preset.config[:speed] == 2.5
    end

    test "pixel fun save as new clears dirty state" do
      InstallationTransport.play_now(PixelFun, @classic)
      InstallationTransport.set_tweakable(:translate_scale, 4.0)

      assert :ok = InstallationTransport.save_now_playing_as_new("Drifty ripple")
      assert state().now_playing.dirty == false
    end

    test "pixel fun exposes formula tweakable" do
      InstallationTransport.play_now(PixelFun, @classic)

      playing = state().now_playing
      assert length(playing.tweakables) == 5
      assert Enum.any?(playing.tweakables, &(&1.key == :program and &1.type == :formula))
      assert playing.effective[:program] == "sin(10*t-hypot(x,y))"
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
      {:ok, original_ast} = Program.parse("sin(10*t-hypot(x,y))")

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

    test "pixel fun save as new persists tweaked formula" do
      InstallationTransport.play_now(PixelFun, @classic)
      InstallationTransport.set_tweakable(:program, "sin(x+t)")

      assert :ok = InstallationTransport.save_now_playing_as_new("Custom wave")
      assert state().now_playing.dirty == false

      preset =
        apply(@presets, :list_presets, [PixelFun])
        |> Enum.find(&(&1.name == "Custom wave"))

      assert preset.config[:program] == "sin(x+t)"
    end

    test "tweak recovers when now_playing_app_id is stale" do
      InstallationTransport.play_now(PixelFun, @classic)
      stale_id = state().now_playing.app_id
      AppSupervisor.stop_app(stale_id)

      InstallationTransport.set_tweakable(:zoom_scale, 3.5)

      s = state().now_playing
      assert s.effective[:zoom_scale] == 3.5
      assert is_binary(s.app_id)
      assert s.app_id != stale_id

      {:ok, app_id} = AppSupervisor.find_running_app(PixelFun)
      assert app_id == s.app_id
      assert AppSupervisor.config(app_id)[:zoom_scale] == 3.5
    end

    test "pixel fun rejects save when formula is invalid" do
      InstallationTransport.play_now(PixelFun, @classic)
      InstallationTransport.set_tweakable(:program, "sin(+")

      assert {:error, :invalid_formula} = InstallationTransport.save_now_playing_as_new("Bad scene")
    end

    test "perlin noise tweak applies scale and speed live" do
      InstallationTransport.play_now(PerlinNoise, @perlin)

      playing = state().now_playing
      assert playing.effective[:scale] == 0.1
      assert playing.effective[:octaves] == 4
      assert playing.effective[:speed] == 1.0
      assert playing.effective[:seed] == 42
      assert length(playing.tweakables) == 5
      assert playing.persistable
      assert playing.renamable

      InstallationTransport.set_tweakable(:scale, 0.25)
      InstallationTransport.set_tweakable(:speed, 2.0)

      tweaked = state().now_playing
      assert tweaked.dirty == true
      assert tweaked.effective[:scale] == 0.25
      assert tweaked.effective[:speed] == 2.0

      {:ok, app_id} = AppSupervisor.find_running_app(PerlinNoise)
      config = AppSupervisor.config(app_id)
      assert config[:scale] == 0.25
      assert config[:speed] == 2.0
    end

    test "save and rename perlin preset" do
      InstallationTransport.play_now(PerlinNoise, @perlin)
      InstallationTransport.set_tweakable(:octaves, 6)

      assert :ok = InstallationTransport.save_now_playing_as_new("Chunky clouds")
      assert :ok = InstallationTransport.rename_now_playing_preset("Soft drift")

      s = state()
      assert s.now_playing.preset_name == "Soft drift"
      assert s.live.mode_name == "Soft drift"
    end

    test "ocean tweak applies wave_strength and water_level live" do
      InstallationTransport.play_now(Ocean, @ocean)

      playing = state().now_playing
      assert playing.effective[:wave_strength] == 1.0
      assert playing.effective[:damping] == 0.95
      assert playing.effective[:water_level] == 0.6
      assert length(playing.tweakables) == 3
      assert playing.persistable
      assert playing.renamable

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

    test "save and rename ocean preset" do
      InstallationTransport.play_now(Ocean, @ocean)
      InstallationTransport.set_tweakable(:damping, 0.88)

      assert :ok = InstallationTransport.save_now_playing_as_new("Calm sea")
      assert :ok = InstallationTransport.rename_now_playing_preset("Glassy water")

      s = state()
      assert s.now_playing.preset_name == "Glassy water"
      assert s.live.mode_name == "Glassy water"
    end

    test "sand tweak applies spawn_rate and button_force live" do
      InstallationTransport.play_now(Sand, @sand)

      playing = state().now_playing
      assert playing.effective[:spawn_rate] == 0.25
      assert playing.effective[:button_force] == 40
      assert playing.effective[:auto_drain] == true
      assert playing.effective[:color_mode] == :rainbow
      assert length(playing.tweakables) == 4
      assert playing.persistable
      assert playing.renamable

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

    test "save and overwrite sand builtin" do
      InstallationTransport.play_now(Sand, @sand)
      InstallationTransport.set_tweakable(:button_force, 55)

      np = state().now_playing
      assert np.persistable
      assert np.overwriteable
      assert np.deletable
      assert np.renamable

      assert :ok = InstallationTransport.overwrite_now_playing_mode()
      assert state().now_playing.effective[:button_force] == 55
      assert state().now_playing.dirty == false

      preset = preset_get(Sand, @sand)
      assert preset.config[:button_force] == 55
    end

    test "sparkle mist tweak applies foreground_hue and background_speed live" do
      InstallationTransport.play_now(SparkleMist, @sparkle_mist)

      playing = state().now_playing
      assert playing.effective[:foreground_hue] == 25
      assert playing.effective[:background_speed] == 5.0
      assert playing.effective[:particle_speed_scale] == 1.0
      assert playing.effective[:background_hue_a] == 200
      assert length(playing.tweakables) == 4
      assert playing.persistable
      assert playing.renamable

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

    test "save and overwrite sparkle mist builtin" do
      InstallationTransport.play_now(SparkleMist, @sparkle_mist)
      InstallationTransport.set_tweakable(:particle_speed_scale, 2.5)

      np = state().now_playing
      assert np.persistable
      assert np.overwriteable
      assert np.deletable
      assert np.renamable

      assert :ok = InstallationTransport.overwrite_now_playing_mode()
      assert state().now_playing.effective[:particle_speed_scale] == 2.5
      assert state().now_playing.dirty == false

      preset = preset_get(SparkleMist, @sparkle_mist)
      assert preset.config[:particle_speed_scale] == 2.5
    end
  end

  defp preset_sync_all!, do: apply(@presets, :sync_all!, [])
  defp preset_list(app), do: apply(@presets, :list_presets, [app])
  defp preset_get(app, mode_id), do: apply(@presets, :get, [app, mode_id])
end
