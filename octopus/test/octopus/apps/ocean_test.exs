defmodule Octopus.Apps.OceanTest do
  use Octopus.DataCase, async: true

  alias Octopus.Apps.Ocean.State

  @ocean Module.concat(["Octopus", "Apps", "Ocean"])
  @presets Module.concat(["Octopus", "AppModePresets"])

  setup do
    original_installation = Application.get_env(:octopus, :installation)

    on_exit(fn ->
      Application.put_env(:octopus, :installation, original_installation)
    end)

    :ok
  end

  defp with_installation(installation, fun) do
    Application.put_env(:octopus, :installation, installation)
    fun.()
  end

  defp base_state(overrides) do
    defaults = %{
      time: 0.0,
      wave_strength: 1.0,
      damping: 0.95,
      width: 96,
      height: 8,
      water_level_ratio: 0.6,
      water_level: 4.8,
      background_waves: [],
      interaction_waves: [],
      start_time: 0,
      button_flashes: [],
      last_activity_time: 0,
      inactivity_timer_ref: nil
    }

    struct!(State, Map.merge(defaults, Map.new(overrides)))
  end

  test "list_modes/0 includes ocean mode" do
    [mode] = ocean_list_modes()
    assert mode.id == "ocean:ocean"
    assert mode.builtin == true
  end

  test "mode_config/1 returns defaults" do
    defaults = %{wave_strength: 1.0, damping: 0.95, water_level: 0.6}

    assert ocean_mode_config("ocean:ocean") == defaults
    assert ocean_mode_config("ocean") == defaults
    assert ocean_mode_config("unknown") == %{}
  end

  test "mode_tweakables/1 exposes wave_strength, damping, water_level" do
    keys =
      ocean_mode_tweakables("ocean")
      |> Enum.map(& &1.key)

    assert keys == [:wave_strength, :damping, :water_level]
  end

  test "handle_config/2 applies partial updates" do
    state = base_state(background_waves: [%{}])

    {:noreply, updated} =
      ocean_handle_config(%{wave_strength: 1.0, damping: 0.9, water_level: 0.6}, state)

    assert updated.damping == 0.9
    assert updated.wave_strength == 1.0
    assert updated.background_waves == [%{}]
  end

  test "handle_config/2 regenerates waves when wave_strength changes" do
    state = base_state(background_waves: [%{id: :old}])

    {:noreply, updated} =
      ocean_handle_config(%{wave_strength: 2.0, damping: 0.95, water_level: 0.6}, state)

    assert updated.wave_strength == 2.0
    assert updated.background_waves != [%{id: :old}]
    assert length(updated.background_waves) > 0
  end

  test "handle_config/2 updates water level from ratio" do
    state = base_state(height: 10, water_level_ratio: 0.6, water_level: 6.0)

    {:noreply, updated} =
      ocean_handle_config(%{wave_strength: 1.0, damping: 0.95, water_level: 0.8}, state)

    assert updated.water_level_ratio == 0.8
    assert updated.water_level == 8.0
  end

  test "get_config/1 returns ratio for water_level" do
    state = base_state(water_level_ratio: 0.75)

    assert %{wave_strength: 1.0, damping: 0.95, water_level: 0.75} = ocean_get_config(state)
  end

  test "now_playing_meta/1 summarizes settings and interaction hint" do
    assert ocean_now_playing_meta(%{wave_strength: 1.5, damping: 0.9, water_level: 0.6}) == [
             "strength 1.50",
             "damping 0.90",
             "level 60%",
             "Press panels for waves"
           ]
  end

  test "compatible?/0 on Nation2026 (default)" do
    assert ocean_compatible?()
  end

  test "compatible?/0 on Pixie 8x8" do
    with_installation(Octopus.Installation.Pixie, fn ->
      assert ocean_compatible?()
    end)
  end

  defp ocean_list_modes, do: apply(@ocean, :list_modes, [])
  defp ocean_mode_config(mode_id), do: apply(@ocean, :mode_config, [mode_id])
  defp ocean_mode_tweakables(mode_id), do: apply(@ocean, :mode_tweakables, [mode_id])
  defp ocean_handle_config(config, state), do: apply(@ocean, :handle_config, [config, state])
  defp ocean_get_config(state), do: apply(@ocean, :get_config, [state])
  defp ocean_now_playing_meta(config), do: apply(@ocean, :now_playing_meta, [config])
  defp ocean_compatible?, do: apply(@ocean, :compatible?, [])
end
