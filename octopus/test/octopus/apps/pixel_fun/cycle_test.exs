defmodule Octopus.Apps.PixelFun.CycleTest do
  use ExUnit.Case, async: true

  alias Octopus.Apps.PixelFun

  test "config_schema includes cycle fields with defaults" do
    defaults = Octopus.App.default_config(PixelFun.config_schema())

    assert defaults.cycle_preset_ids == []
    assert defaults.cycle_interval_minutes == 5.0
    refute Map.has_key?(defaults, :cycle_functions)
  end

  test "get_config includes active_preset_id derived from scene" do
    state =
      struct!(PixelFun.State,
        program: 0,
        source: "sin(10*t-hypot(x,y))",
        colors: {Chameleon.HSV.new(0, 70, 100), Chameleon.HSV.new(90, 70, 100)},
        last_colors: {Chameleon.HSV.new(0, 70, 100), Chameleon.HSV.new(90, 70, 100)},
        target_colors: {Chameleon.HSV.new(0, 70, 100), Chameleon.HSV.new(90, 70, 100)},
        lerp_time: 5.0,
        translate_scale: 0.0,
        rotate_scale: 0.0,
        zoom_scale: 1.0,
        color_interval: 5.0,
        cycle_preset_ids: [],
        cycle_interval_minutes: 5.0,
        cycle_index: 0,
        cycle_timer_ref: nil,
        offset: {0, 0},
        move: {0, 0},
        audio_input: %{low: 0.0, mid: 0.0, high: 0.0},
        seconds: 0.0,
        buttons: %{},
        panel_interaction_factors: %{},
        panel_proximities: %{},
        speed: 1.0
      )

    assert PixelFun.get_config(state).active_preset_id == "builtin:classic_ripple"
  end

  test "get_config active_preset_id follows cycle_index when looping" do
    state =
      struct!(PixelFun.State,
        program: 0,
        source: "sin(x*0.7+t*2)*cos(y*0.7-t*1.3)",
        colors: {Chameleon.HSV.new(0, 70, 100), Chameleon.HSV.new(90, 70, 100)},
        last_colors: {Chameleon.HSV.new(0, 70, 100), Chameleon.HSV.new(90, 70, 100)},
        target_colors: {Chameleon.HSV.new(0, 70, 100), Chameleon.HSV.new(90, 70, 100)},
        lerp_time: 5.0,
        translate_scale: 0.0,
        rotate_scale: 0.0,
        zoom_scale: 1.0,
        color_interval: 5.0,
        cycle_preset_ids: ["builtin:classic_ripple", "builtin:cross_waves"],
        cycle_interval_minutes: 1.0,
        cycle_index: 1,
        cycle_timer_ref: nil,
        offset: {0, 0},
        move: {0, 0},
        audio_input: %{low: 0.0, mid: 0.0, high: 0.0},
        seconds: 0.0,
        buttons: %{},
        panel_interaction_factors: %{},
        panel_proximities: %{},
        speed: 1.0
      )

    assert PixelFun.get_config(state).active_preset_id == "builtin:cross_waves"
    assert PixelFun.get_config(state).cycle_index == 1
  end
end
