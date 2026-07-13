defmodule Octopus.Apps.PixelFun3D.CycleTest do
  use Octopus.DataCase, async: true

  alias Octopus.Apps.PixelFun3D.ScenePresets
  alias Octopus.Apps.PixelFun3D.State

  @pixel_fun Module.concat(["Octopus", "Apps", "PixelFun3D"])
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
          zoom_base: 1.0,
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
          time_direction: :forward,
          formula_seconds: 0.0
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

    test "resets orientation and does not keep wandered sway on neutral scene" do
      wanderer = Octopus.Wander.new(2.5)

      state =
        base_state(%{
          live_scene_id: "builtin:marmor",
          sway_auto: true,
          tilt_scale: 0.0,
          auto_wanderers: %{sway: wanderer},
          yaw_angle: 1.2,
          roll_angle: 0.8
        })

      {:noreply, updated} = pixel_fun_handle_cast({:apply_mode, "builtin:swaytest"}, state)

      assert updated.sway_auto == false
      assert_in_delta updated.tilt_scale, 0.0, 0.0001
      assert_in_delta updated.yaw_angle, 0.0, 0.0001
      assert_in_delta updated.roll_angle, 0.0, 0.0001
      assert updated.source =~ "tanh"
    end

    test "loads wasserwaage sway from code builtin defs" do
      state = base_state(%{tilt_scale: 0.0, tilt_speed: 0.5})

      {:noreply, updated} =
        pixel_fun_handle_cast({:apply_mode, "builtin:wasserwaage"}, state)

      assert_in_delta updated.tilt_scale, 2.5, 0.0001
      assert_in_delta updated.tilt_speed, 0.4, 0.0001
      assert updated.tilt_mode == :wobble
      assert updated.source == "tanh(y*1.8)"
    end
  end

  describe "handle_config/2" do
    test "applies orbit, roll, and zoom immediately" do
      state = base_state(%{live_scene_id: @classic})

      {:noreply, updated} =
        pixel_fun_handle_config(%{orbit_rate: 1.5, roll_rate: 2.0, zoom_base: 1.5}, state)

      assert updated.orbit_rate == 1.5
      assert updated.roll_rate == 2.0
      assert updated.zoom_base == 1.5
    end

    test "clamps sub-minimum zoom_base on handle_config" do
      state = base_state(%{live_scene_id: @classic})

      {:noreply, updated} = pixel_fun_handle_config(%{zoom_base: 0.5}, state)

      assert updated.zoom_base == 0.7
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

    # Regression: integrating the manual rates while frozen kept the image
    # translating/rotating for every scene with nonzero drift, so "Freeze
    # time" visibly did not freeze at all.
    test "frozen tick does not integrate manual translate X and rotation" do
      state =
        base_state(%{
          time_frozen: true,
          seconds: 42.0,
          orbit_rate: 8.0,
          roll_rate: 90.0,
          yaw_angle: 0.5,
          roll_angle: 0.25
        })

      {:noreply, updated} = pixel_fun_handle_info(:tick, state)

      assert updated.yaw_angle == 0.5
      assert updated.roll_angle == 0.25
      assert updated.seconds == 42.0
      assert updated.formula_seconds == state.formula_seconds
    end

    test "frozen tick does not integrate auto-wandered rates" do
      state =
        base_state(%{
          time_frozen: true,
          orbit_rate: 8.0,
          roll_rate: 90.0,
          trans_auto: true,
          rot_auto: true,
          auto_wanderers: %{
            trans: Octopus.Wander.new({8.0, 0.0}),
            rot: Octopus.Wander.new({90.0})
          },
          yaw_angle: 1.0,
          roll_angle: 2.0
        })

      {:noreply, updated} = pixel_fun_handle_info(:tick, state)

      assert_in_delta updated.yaw_angle, 1.0, 1.0e-12
      assert_in_delta updated.roll_angle, 2.0, 1.0e-12
    end

    test "freezing captures scrub refs so the freeze moment shows no jump" do
      state = base_state(%{orbit_rate: 2.0, roll_rate: 10.0, yaw_angle: 1.0, roll_angle: 0.5})

      # The transport always sends the full config, so keep the rates in.
      {:noreply, frozen} =
        pixel_fun_handle_config(%{time_frozen: true, orbit_rate: 2.0, roll_rate: 10.0}, state)

      assert frozen.frozen_orbit_ref == 2.0
      assert frozen.frozen_roll_ref == 10.0

      {yaw, roll} = pixel_fun_frozen_scrub_angles(frozen, 1.0, 0.5, 0.1)
      assert_in_delta yaw, 1.0, 1.0e-12
      assert_in_delta roll, 0.5, 1.0e-12
    end

    test "slider deltas while frozen scrub the image and scrub back" do
      state = base_state(%{orbit_rate: 2.0, roll_rate: 10.0, yaw_angle: 1.0, roll_angle: 0.5})

      {:noreply, frozen} =
        pixel_fun_handle_config(%{time_frozen: true, orbit_rate: 2.0, roll_rate: 10.0}, state)

      {:noreply, scrubbed} = pixel_fun_handle_config(%{orbit_rate: 10.0, roll_rate: 40.0}, frozen)

      # Integrated angles stay untouched; only the rendered offset moves.
      assert scrubbed.yaw_angle == 1.0
      assert scrubbed.roll_angle == 0.5

      {yaw, roll} = pixel_fun_frozen_scrub_angles(scrubbed, 1.0, 0.5, 0.1)
      assert_in_delta yaw, 1.0 + (10.0 - 2.0) * 0.1, 1.0e-9
      assert_in_delta roll, 0.5 + (40.0 - 10.0) * :math.pi() / 180.0, 1.0e-9

      {:noreply, back} = pixel_fun_handle_config(%{orbit_rate: 2.0, roll_rate: 10.0}, scrubbed)
      {yaw, roll} = pixel_fun_frozen_scrub_angles(back, 1.0, 0.5, 0.1)
      assert_in_delta yaw, 1.0, 1.0e-9
      assert_in_delta roll, 0.5, 1.0e-9
    end

    test "unfreezing bakes the scrub offset into the angles" do
      state = base_state(%{orbit_rate: 2.0, roll_rate: 10.0, yaw_angle: 1.0, roll_angle: 0.5})

      {:noreply, frozen} =
        pixel_fun_handle_config(%{time_frozen: true, orbit_rate: 2.0, roll_rate: 10.0}, state)

      {:noreply, scrubbed} = pixel_fun_handle_config(%{orbit_rate: 10.0, roll_rate: 40.0}, frozen)

      {:noreply, resumed} =
        pixel_fun_handle_config(%{time_frozen: false, orbit_rate: 10.0, roll_rate: 40.0}, scrubbed)

      assert resumed.frozen_orbit_ref == nil
      assert resumed.frozen_roll_ref == nil
      # Yaw offset uses the installation alpha; just assert direction there.
      assert resumed.yaw_angle > 1.0
      assert_in_delta resumed.roll_angle, 0.5 + 30.0 * :math.pi() / 180.0, 1.0e-9
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

    test "sat auto wanders between min/max; off hands live value to slider" do
      state =
        base_state(%{
          saturation_percent: 70,
          sat_auto: false,
          sat_auto_min: 10.0,
          sat_auto_max: 90.0,
          sat_auto_interval: 4.0,
          seconds: 1.0
        })

      {:noreply, on} =
        pixel_fun_handle_config(
          %{
            sat_auto: true,
            saturation_percent: 70,
            sat_auto_min: 10.0,
            sat_auto_max: 90.0,
            sat_auto_interval: 4.0,
            pixel_fun_units: 2
          },
          state
        )

      assert on.sat_auto == true
      assert %Octopus.Wander{value: {v0}} = on.auto_wanderers[:sat]
      assert_in_delta v0, 70.0, 1.0e-12

      {:noreply, stepped} =
        Enum.reduce(1..20, {:noreply, on}, fn _, {:noreply, s} ->
          pixel_fun_handle_info(:tick, s)
        end)

      assert %Octopus.Wander{value: {live}} = stepped.auto_wanderers[:sat]
      assert live >= 10.0 - 1.0e-6
      assert live <= 90.0 + 1.0e-6

      {:noreply, off} =
        pixel_fun_handle_config(%{sat_auto: false, pixel_fun_units: 2}, stepped)

      assert off.sat_auto == false
      refute Map.has_key?(off.auto_wanderers, :sat)
      assert off.saturation_percent == trunc(live)
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
    test "toggle-off hands live wanderer values to sliders" do
      state =
        base_state(%{
          orbit_rate: 0.0,
          elev_base: 0.0,
          trans_auto: true,
          seconds: 5.0,
          auto_wanderers: %{
            trans: %Octopus.Wander{
              value: {2.5, -1.0},
              seg_from: {0.0, 0.0},
              target: {2.5, -1.0},
              seg_start: 0.0,
              seg_dur: 1.0,
              easing: :smoothstep
            }
          }
        })

      {:noreply, off} =
        pixel_fun_handle_config(%{trans_auto: false, pixel_fun_units: 2}, state)

      assert off.trans_auto == false
      assert_in_delta off.orbit_rate, 2.5, 1.0e-12
      assert_in_delta off.elev_base, -1.0, 1.0e-12
      refute Map.has_key?(off.auto_wanderers, :trans)
    end

    test "formula_seconds reverses continuously without jump" do
      state = base_state(%{time_direction: :forward, seconds: 10.0, formula_seconds: 10.0, speed: 1.0})

      state =
        Enum.reduce(1..100, state, fn _, s ->
          {:noreply, next} = pixel_fun_handle_info(:tick, s)
          next
        end)

      before = state.formula_seconds
      dt = 1 / 30

      {:noreply, flipped} =
        pixel_fun_handle_config(%{time_direction: :backward, pixel_fun_units: 2}, state)

      {:noreply, after_tick} = pixel_fun_handle_info(:tick, flipped)

      assert_in_delta after_tick.formula_seconds - before, -dt, 1.0e-6
    end
  end

  defp preset_sync_all!, do: apply(@presets, :sync_all!, [])
  defp pixel_fun_config_schema, do: apply(@pixel_fun, :config_schema, [])
  defp pixel_fun_get_config(state), do: apply(@pixel_fun, :get_config, [state])
  defp pixel_fun_mode_config(mode_id), do: apply(@pixel_fun, :mode_config, [mode_id])
  defp pixel_fun_handle_cast(message, state), do: apply(@pixel_fun, :handle_cast, [message, state])
  defp pixel_fun_handle_config(config, state), do: apply(@pixel_fun, :handle_config, [config, state])
  defp pixel_fun_handle_info(message, state), do: apply(@pixel_fun, :handle_info, [message, state])

  defp pixel_fun_frozen_scrub_angles(state, yaw, roll, alpha),
    do: apply(@pixel_fun, :frozen_scrub_angles, [state, yaw, roll, alpha])
end
