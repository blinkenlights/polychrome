defmodule Octopus.Apps.PixelFun.CycleTest do
  use Octopus.DataCase, async: true

  alias Octopus.Apps.PixelFun.ScenePresets
  alias Octopus.Apps.PixelFun.State

  @pixel_fun Module.concat(["Octopus", "Apps", "PixelFun"])
  @presets Module.concat(["Octopus", "AppModePresets"])
  @app Module.concat(["Octopus", "App"])

  @classic "builtin:classic_ripple"
  @cross "builtin:cross_waves"

  setup do
    preset_sync_all!()
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
          source: "sin(0.4*t-hypot(x,y))",
          colors: {color(), color()},
          last_colors: {color(), color()},
          target_colors: {color(), color()},
          lerp_time: 5.0,
          orbit_rate: 0.0,
          roll_rate: 0.0,
          roll_pivot: 0,
          tilt_scale: 0.0,
          tilt_speed: 0.5,
          tilt_mode: :wobble,
          elev_base: 0.0,
          zoom_base: 0.0,
          zoom_pivot: 0,
          pattern_speed: 1.0,
          trans_auto: false,
          trans_auto_range_x: 1.0,
          trans_auto_range_y: 2.0,
          trans_auto_interval: 30.0,
          rot_auto: false,
          rot_auto_range: 1.0,
          rot_auto_interval: 30.0,
          zoom_auto: false,
          zoom_auto_range: 0.8,
          zoom_auto_interval: 30.0,
          sway_auto: false,
          sway_auto_range: 2.0,
          sway_auto_interval: 30.0,
          auto_wanderers: %{},
          yaw_angle: 0.0,
          roll_angle: 0.0,
          color_mode: :random,
          saturation_percent: 70,
          palette_phase: 0.0,
          color_interval: 5.0,
          palette_auto: true,
          live_scene_id: nil,
          audio_input: %{low: 0.0, mid: 0.0, high: 0.0},
          seconds: 0.0,
          buttons: %{},
          panel_interaction_factors: %{},
          panel_proximities: %{},
          speed: 1.0,
          display_info: %{width: 8, height: 8},
          pixel_dirs: nil,
          time_frozen: false,
          show_advanced: false,
          time_direction: :forward
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
    test "applies orbit, roll, and zoom immediately" do
      state = base_state(%{live_scene_id: @classic})

      {:noreply, updated} =
        pixel_fun_handle_config(%{orbit_rate: 1.5, roll_rate: 2.0, zoom_base: 0.5}, state)

      assert updated.orbit_rate == 1.5
      assert updated.roll_rate == 2.0
      assert updated.zoom_base == 0.5
    end

    test "migrates legacy transform keys on handle_config" do
      state = base_state(%{live_scene_id: @classic})

      {:noreply, updated} =
        pixel_fun_handle_config(%{translate_scale: 4.0, rotate_scale: 2.0, zoom_scale: 5.0}, state)

      assert updated.trans_auto == true
      assert_in_delta updated.trans_auto_range_y, 4.0, 0.0001
      assert_in_delta updated.roll_rate, 2.0 * 180 / :math.pi(), 0.1
    end

    test "applies color_interval and palette_phase via handle_config" do
      state = base_state(%{live_scene_id: @classic, color_interval: 5.0, palette_phase: 0.0})

      {:noreply, updated} =
        pixel_fun_handle_config(%{color_interval: 10.0, palette_phase: 0.25}, state)

      assert updated.color_interval == 10.0
      assert_in_delta updated.palette_phase, 0.25, 1.0e-6
      {a, b} = updated.colors
      assert a.h == 90
      assert b.h == 270
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
    test "freezing stops palette phase advance" do
      state =
        base_state(%{
          time_frozen: false,
          color_mode: :random,
          palette_auto: true,
          palette_phase: 0.1,
          color_interval: 5.0,
          speed: 1.0
        })

      {:noreply, running} = pixel_fun_handle_info(:tick, state)
      assert running.palette_phase > 0.1

      {:noreply, frozen} = pixel_fun_handle_config(%{time_frozen: true}, running)
      phase = frozen.palette_phase
      {:noreply, still} = pixel_fun_handle_info(:tick, frozen)
      assert_in_delta still.palette_phase, phase, 1.0e-12
    end

    test "tick does not advance time when frozen" do
      state = base_state(%{time_frozen: true, seconds: 42.0, palette_phase: 0.3})

      {:noreply, updated} = pixel_fun_handle_info(:tick, state)

      assert updated.seconds == 42.0
      assert_in_delta updated.palette_phase, 0.3, 1.0e-12
    end

    test "tick advances time when not frozen" do
      state = base_state(%{time_frozen: false, seconds: 10.0})

      {:noreply, updated} = pixel_fun_handle_info(:tick, state)

      assert updated.seconds > 10.0
    end

    test "palette auto advances phase and updates complementary hues" do
      state =
        base_state(%{
          color_mode: :random,
          palette_auto: true,
          palette_phase: 0.0,
          color_interval: 1.0,
          saturation_percent: 70,
          speed: 1.0
        })

      {:noreply, updated} = pixel_fun_handle_info(:tick, state)
      assert updated.palette_phase > 0.0
      {a, b} = updated.colors
      assert rem(a.h + 180, 360) == b.h
    end

    test "palette auto off keeps phase fixed" do
      state =
        base_state(%{
          color_mode: :random,
          palette_auto: false,
          palette_phase: 0.4,
          color_interval: 1.0,
          speed: 1.0
        })

      {:noreply, updated} = pixel_fun_handle_info(:tick, state)
      assert_in_delta updated.palette_phase, 0.4, 1.0e-12
    end

    test "auto toggle on seeds wanderer at manual base; off clears wanderer" do
      state = base_state(%{orbit_rate: 1.5, elev_base: 0.5, trans_auto: false, seconds: 5.0})

      {:noreply, on} =
        pixel_fun_handle_config(
          %{trans_auto: true, orbit_rate: 1.5, elev_base: 0.5, pixel_fun_units: 2},
          state
        )

      assert on.trans_auto == true
      assert %Octopus.Wander{value: {vx, vy}} = on.auto_wanderers[:trans]
      assert_in_delta vx, 1.5, 1.0e-12
      assert_in_delta vy, 0.5, 1.0e-12

      {:noreply, stepped} = pixel_fun_handle_info(:tick, on)
      assert_in_delta elem(stepped.auto_wanderers[:trans].value, 0), 1.5, 0.05

      {:noreply, off} =
        pixel_fun_handle_config(%{trans_auto: false, orbit_rate: 1.5, elev_base: 0.5}, stepped)

      assert off.trans_auto == false
      refute Map.has_key?(off.auto_wanderers, :trans)
      assert_in_delta off.orbit_rate, 1.5, 1.0e-12
    end

    test "frozen time does not advance wanderers" do
      state =
        base_state(%{
          time_frozen: false,
          trans_auto: true,
          orbit_rate: 0.0,
          elev_base: 0.0,
          trans_auto_range_x: 2.0,
          trans_auto_range_y: 2.0,
          trans_auto_interval: 4.0,
          seconds: 1.0,
          auto_wanderers: %{trans: Octopus.Wander.new({0.0, 0.0})}
        })

      {:noreply, running} = pixel_fun_handle_info(:tick, state)
      w1 = running.auto_wanderers[:trans]

      frozen = %{running | time_frozen: true}
      {:noreply, still} = pixel_fun_handle_info(:tick, frozen)
      assert still.auto_wanderers[:trans] == w1
      assert still.seconds == running.seconds
    end
  end

  defp preset_sync_all!, do: apply(@presets, :sync_all!, [])
  defp pixel_fun_config_schema, do: apply(@pixel_fun, :config_schema, [])
  defp pixel_fun_get_config(state), do: apply(@pixel_fun, :get_config, [state])
  defp pixel_fun_mode_config(mode_id), do: apply(@pixel_fun, :mode_config, [mode_id])
  defp pixel_fun_handle_cast(message, state), do: apply(@pixel_fun, :handle_cast, [message, state])
  defp pixel_fun_handle_config(config, state), do: apply(@pixel_fun, :handle_config, [config, state])
  defp pixel_fun_handle_info(message, state), do: apply(@pixel_fun, :handle_info, [message, state])
end
