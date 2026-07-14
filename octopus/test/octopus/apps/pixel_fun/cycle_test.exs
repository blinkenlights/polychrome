defmodule Octopus.Apps.PixelFun.CycleTest do
  use Octopus.DataCase, async: true

  alias Octopus.Apps.PixelFun.ScenePresets
  alias Octopus.Apps.PixelFun.State

  @pixel_fun Module.concat(["Octopus", "Apps", "PixelFun"])
  @app Module.concat(["Octopus", "App"])

  @classic "builtin:classic_ripple"
  @cross "builtin:cross_waves"

  setup do
    {:ok, _} = Registry.register(Octopus.AppRegistry, "test-#{System.unique_integer([:positive])}", @pixel_fun)
    :ok
  end

  defp color, do: Chameleon.HSV.new(0, 70, 100)

  defp base_state(overrides) do
    struct!(
      State,
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
          color_mode: :random,
          saturation_percent: 70,
          color_interval: 5.0,
          live_scene_id: nil,
          offset: {0, 0},
          move: {0, 0},
          audio_input: %{low: 0.0, mid: 0.0, high: 0.0},
          seconds: 0.0,
          buttons: %{},
          panel_interaction_factors: %{},
          panel_proximities: %{},
          speed: 1.0,
          display_info: %{width: 8, height: 8},
          time_frozen: false
        },
        overrides
      )
    )
  end

  describe "config schema" do
    test "has no internal transport fields" do
      defaults = apply(@app, :default_config, [pixel_fun_config_schema()])

      refute Map.has_key?(defaults, :cycle_preset_ids)
      refute Map.has_key?(defaults, :cycle_interval_seconds)
      refute Map.has_key?(defaults, :cycle_interval_minutes)
    end
  end

  describe "get_config/1" do
    test "exposes live scene id" do
      config = pixel_fun_get_config(base_state(%{live_scene_id: @classic}))

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
      config = pixel_fun_mode_config(@classic)

      assert is_binary(config.program)
      assert is_number(config.color_interval)
    end
  end

  describe "apply_mode" do
    test "loads scene and sets live_scene_id" do
      state = base_state(%{live_scene_id: @classic})

      {:noreply, updated} = pixel_fun_handle_cast({:apply_mode, @cross}, state)

      assert updated.live_scene_id == @cross
      assert updated.source == pixel_fun_mode_config(@cross).program
    end
  end

  describe "handle_config/2" do
    test "applies drift, rotation, and zoom immediately" do
      state = base_state(%{live_scene_id: @classic})

      {:noreply, updated} =
        pixel_fun_handle_config(%{translate_scale: 4.0, rotate_scale: 2.0, zoom_scale: 5.0}, state)

      assert updated.translate_scale == 4.0
      assert updated.rotate_scale == 2.0
      assert updated.zoom_scale == 5.0
    end

    test "reschedules color timer and resets lerp_time when color_interval changes" do
      state = base_state(%{live_scene_id: @classic, color_interval: 5.0, lerp_time: 2.0, color_timer_ref: nil})

      {:noreply, updated} = pixel_fun_handle_config(%{color_interval: 10.0}, state)

      assert updated.color_interval == 10.0
      assert updated.lerp_time == 10.0
      assert is_reference(Map.get(updated, :color_timer_ref))
    end

    test "applies saturation_percent via handle_config" do
      state = base_state(%{live_scene_id: @classic, saturation_percent: 70})

      {:noreply, updated} = pixel_fun_handle_config(%{saturation_percent: 30}, state)

      assert updated.saturation_percent == 30
      assert pixel_fun_get_config(updated).saturation_percent == 30
    end

    test "exposes time_frozen in get_config" do
      config = pixel_fun_get_config(base_state(%{time_frozen: true}))
      assert config.time_frozen == true
    end
  end

  describe "time freeze" do
    test "freezing cancels color timer" do
      ref = Process.send_after(self(), :noop, 60_000)
      state = base_state(%{time_frozen: false, color_timer_ref: ref})

      {:noreply, updated} = pixel_fun_handle_config(%{time_frozen: true}, state)

      assert updated.time_frozen == true
      assert updated.color_timer_ref == nil
    end

    test "unfreezing restarts color timer" do
      state = base_state(%{time_frozen: true, color_timer_ref: nil, color_mode: :random})

      {:noreply, updated} = pixel_fun_handle_config(%{time_frozen: false}, state)

      assert updated.time_frozen == false
      assert is_reference(updated.color_timer_ref)
    end

    test "tick does not advance time when frozen" do
      state = base_state(%{time_frozen: true, seconds: 42.0, lerp_time: 3.0})

      {:noreply, updated} = pixel_fun_handle_info(:tick, state)

      assert updated.seconds == 42.0
      assert updated.lerp_time == 3.0
    end

    test "tick advances time when not frozen" do
      state = base_state(%{time_frozen: false, seconds: 10.0})

      {:noreply, updated} = pixel_fun_handle_info(:tick, state)

      assert updated.seconds > 10.0
    end

    test "update_colors is ignored while frozen" do
      state = base_state(%{time_frozen: true, color_mode: :random, colors: {color(), color()}})

      {:noreply, updated} = pixel_fun_handle_info(:update_colors, state)

      assert updated.colors == state.colors
    end
  end

  defp pixel_fun_config_schema, do: apply(@pixel_fun, :config_schema, [])
  defp pixel_fun_get_config(state), do: apply(@pixel_fun, :get_config, [state])
  defp pixel_fun_mode_config(mode_id), do: apply(@pixel_fun, :mode_config, [mode_id])
  defp pixel_fun_handle_cast(message, state), do: apply(@pixel_fun, :handle_cast, [message, state])
  defp pixel_fun_handle_config(config, state), do: apply(@pixel_fun, :handle_config, [config, state])
  defp pixel_fun_handle_info(message, state), do: apply(@pixel_fun, :handle_info, [message, state])
end
