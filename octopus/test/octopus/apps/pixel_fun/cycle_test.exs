defmodule Octopus.Apps.PixelFun.CycleTest do
  use ExUnit.Case, async: true

  alias Octopus.Apps.PixelFun

  @classic "builtin:classic_ripple"
  @cross "builtin:cross_waves"

  setup do
    # Transport casts broadcast the updated config, which looks up the app id
    # from the registry — register the test process so broadcasting works.
    {:ok, _} = Registry.register(Octopus.AppRegistry, "test-#{System.unique_integer([:positive])}", PixelFun)
    :ok
  end

  defp color, do: Chameleon.HSV.new(0, 70, 100)

  defp base_state(overrides) do
    struct!(
      PixelFun.State,
      Map.merge(
        %{
          program: 0,
          source: "sin(10*t-hypot(x,y))",
          colors: {color(), color()},
          last_colors: {color(), color()},
          target_colors: {color(), color()},
          lerp_time: 5.0,
          translate_scale: 0.0,
          rotate_scale: 0.0,
          zoom_scale: 1.0,
          color_interval: 5.0,
          cycle_preset_ids: [],
          cycle_interval_seconds: 300.0,
          cycle_index: 0,
          cycle_timer_ref: nil,
          playing: true,
          paused_remaining_ms: nil,
          next_change_at_ms: nil,
          live_scene_id: nil,
          offset: {0, 0},
          move: {0, 0},
          audio_input: %{low: 0.0, mid: 0.0, high: 0.0},
          seconds: 0.0,
          buttons: %{},
          panel_interaction_factors: %{},
          panel_proximities: %{},
          speed: 1.0
        },
        overrides
      )
    )
  end

  defp queued_state(overrides) do
    base_state(
      Map.merge(
        %{
          cycle_preset_ids: [@classic, @cross],
          cycle_interval_seconds: 60.0,
          cycle_index: 0,
          live_scene_id: @classic
        },
        overrides
      )
    )
  end

  describe "config schema" do
    test "includes interval seconds default and no minutes field" do
      defaults = Octopus.App.default_config(PixelFun.config_schema())

      assert defaults.cycle_preset_ids == []
      assert defaults.cycle_interval_seconds == 300.0
      refute Map.has_key?(defaults, :cycle_interval_minutes)
      refute Map.has_key?(defaults, :cycle_functions)
    end
  end

  describe "get_config/1" do
    test "exposes transport fields" do
      config = PixelFun.get_config(queued_state(%{playing: false, paused_remaining_ms: 12_345}))

      assert config.cycle_preset_ids == [@classic, @cross]
      assert config.cycle_interval_seconds == 60.0
      assert config.playing == false
      assert config.paused_remaining_ms == 12_345
      assert config.live_scene_id == @classic
    end

    test "active_preset_id follows live_scene_id" do
      config = PixelFun.get_config(queued_state(%{cycle_index: 1, live_scene_id: @cross}))

      assert config.active_preset_id == @cross
      assert config.cycle_index == 1
    end
  end

  describe "toggle_play" do
    test "pause freezes the remaining time and cancels the deadline" do
      deadline = System.os_time(:millisecond) + 60_000
      state = queued_state(%{next_change_at_ms: deadline})

      {:noreply, paused} = PixelFun.handle_cast(:toggle_play, state)

      assert paused.playing == false
      assert paused.next_change_at_ms == nil
      assert_in_delta paused.paused_remaining_ms, 60_000, 1_500
    end

    test "resume reschedules from the frozen remainder" do
      state = queued_state(%{playing: false, paused_remaining_ms: 20_000, next_change_at_ms: nil})

      {:noreply, resumed} = PixelFun.handle_cast(:toggle_play, state)

      assert resumed.playing == true
      assert resumed.paused_remaining_ms == nil
      assert is_integer(resumed.next_change_at_ms)
      assert_in_delta resumed.next_change_at_ms - System.os_time(:millisecond), 20_000, 1_500
    end
  end

  describe "set_interval" do
    test "swaps the value without resetting the running countdown" do
      deadline = System.os_time(:millisecond) + 45_000
      state = queued_state(%{next_change_at_ms: deadline})

      {:noreply, updated} = PixelFun.handle_cast({:set_interval, 30}, state)

      assert updated.cycle_interval_seconds == 30.0
      assert updated.next_change_at_ms == deadline
    end
  end

  describe "next / prev" do
    test "next advances the queue and restarts the countdown fresh" do
      old_deadline = System.os_time(:millisecond) - 1_000
      state = queued_state(%{cycle_index: 0, next_change_at_ms: old_deadline})

      {:noreply, next} = PixelFun.handle_cast(:next_scene, state)

      assert next.cycle_index == 1
      assert next.live_scene_id == @cross
      assert next.next_change_at_ms > System.os_time(:millisecond)
    end

    test "prev wraps to the last scene" do
      {:noreply, prev} = PixelFun.handle_cast(:prev_scene, queued_state(%{cycle_index: 0}))

      assert prev.cycle_index == 1
      assert prev.live_scene_id == @cross
    end
  end

  describe "play_now" do
    test "jumps the queue position when the scene is queued" do
      {:noreply, state} = PixelFun.handle_cast({:play_now, @cross}, queued_state(%{cycle_index: 0}))

      assert state.cycle_index == 1
      assert state.live_scene_id == @cross
    end

    test "loads a non-queued scene without moving the queue position" do
      state = base_state(%{cycle_preset_ids: [@classic], cycle_index: 0, live_scene_id: @classic})

      {:noreply, played} = PixelFun.handle_cast({:play_now, @cross}, state)

      assert played.live_scene_id == @cross
      assert played.cycle_index == 0
    end
  end

  describe "holding (0 or 1 queued)" do
    test "next is a no-op with a single queued scene" do
      state = base_state(%{cycle_preset_ids: [@classic], cycle_index: 0, live_scene_id: @classic})

      {:noreply, unchanged} = PixelFun.handle_cast(:next_scene, state)

      assert unchanged.cycle_index == 0
      assert unchanged.next_change_at_ms == nil
    end

    test "adding a second scene starts the countdown" do
      state = base_state(%{cycle_preset_ids: [@classic], live_scene_id: @classic})

      {:noreply, updated} = PixelFun.handle_cast({:set_queue, [@classic, @cross]}, state)

      assert updated.cycle_preset_ids == [@classic, @cross]
      assert is_integer(updated.next_change_at_ms)
    end
  end
end
