defmodule Octopus.Apps.PixelFun.CycleTest do
  use ExUnit.Case, async: true

  alias Octopus.Apps.PixelFun
  alias Octopus.Apps.PixelFun.ScenePresets

  @classic "builtin:classic_ripple"
  @cross "builtin:cross_waves"

  setup do
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

  describe "config schema" do
    test "has no internal transport fields" do
      defaults = Octopus.App.default_config(PixelFun.config_schema())

      refute Map.has_key?(defaults, :cycle_preset_ids)
      refute Map.has_key?(defaults, :cycle_interval_seconds)
      refute Map.has_key?(defaults, :cycle_interval_minutes)
    end
  end

  describe "get_config/1" do
    test "exposes live scene id" do
      config = PixelFun.get_config(base_state(%{live_scene_id: @classic}))

      assert config.live_scene_id == @classic
      assert config.active_preset_id == @classic
      refute Map.has_key?(config, :playing)
    end
  end

  describe "list_modes/0" do
    test "includes built-in scenes" do
      ids = Enum.map(ScenePresets.builtins(), & &1.id)
      assert @classic in ids
    end
  end

  describe "mode_config/1" do
    test "maps preset id to scene config" do
      config = PixelFun.mode_config(@classic)

      assert is_binary(config.program)
      assert is_number(config.color_interval)
    end
  end

  describe "apply_mode" do
    test "loads scene and sets live_scene_id" do
      state = base_state(%{live_scene_id: @classic})

      {:noreply, updated} = PixelFun.handle_cast({:apply_mode, @cross}, state)

      assert updated.live_scene_id == @cross
      assert updated.source == PixelFun.mode_config(@cross).program
    end
  end

  describe "handle_config/2" do
    test "applies drift, rotation, and zoom immediately" do
      state = base_state(%{live_scene_id: @classic})

      {:noreply, updated} =
        PixelFun.handle_config(%{translate_scale: 4.0, rotate_scale: 2.0, zoom_scale: 5.0}, state)

      assert updated.translate_scale == 4.0
      assert updated.rotate_scale == 2.0
      assert updated.zoom_scale == 5.0
    end

    test "reschedules color timer and resets lerp_time when color_interval changes" do
      state = base_state(%{live_scene_id: @classic, color_interval: 5.0, lerp_time: 2.0, color_timer_ref: nil})

      {:noreply, updated} = PixelFun.handle_config(%{color_interval: 10.0}, state)

      assert updated.color_interval == 10.0
      assert updated.lerp_time == 10.0
      assert is_reference(updated.color_timer_ref)
    end
  end
end
