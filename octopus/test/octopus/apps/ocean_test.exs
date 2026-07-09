defmodule Octopus.Apps.OceanTest do
  use Octopus.DataCase, async: true

  alias Octopus.AppModePresets
  alias Octopus.Apps.Ocean
  alias Octopus.Apps.Ocean.State

  setup do
    AppModePresets.sync_all!()
    :ok
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
    [mode] = Ocean.list_modes()
    assert mode.id == "ocean:ocean"
    assert mode.builtin == true
  end

  test "mode_config/1 returns defaults" do
    defaults = %{wave_strength: 1.0, damping: 0.95, water_level: 0.6}

    assert Ocean.mode_config("ocean:ocean") == defaults
    assert Ocean.mode_config("ocean") == defaults
    assert Ocean.mode_config("unknown") == %{}
  end

  test "mode_tweakables/1 exposes wave_strength, damping, water_level" do
    keys =
      Ocean.mode_tweakables("ocean")
      |> Enum.map(& &1.key)

    assert keys == [:wave_strength, :damping, :water_level]
  end

  test "handle_config/2 applies partial updates" do
    state = base_state(background_waves: [%{}])

    {:noreply, updated} = Ocean.handle_config(%{damping: 0.9}, state)

    assert updated.damping == 0.9
    assert updated.wave_strength == 1.0
    assert updated.background_waves == [%{}]
  end

  test "handle_config/2 regenerates waves when wave_strength changes" do
    state = base_state(background_waves: [%{id: :old}])

    {:noreply, updated} = Ocean.handle_config(%{wave_strength: 2.0}, state)

    assert updated.wave_strength == 2.0
    assert updated.background_waves != [%{id: :old}]
    assert length(updated.background_waves) > 0
  end

  test "handle_config/2 updates water level from ratio" do
    state = base_state(height: 10, water_level_ratio: 0.6, water_level: 6.0)

    {:noreply, updated} = Ocean.handle_config(%{water_level: 0.8}, state)

    assert updated.water_level_ratio == 0.8
    assert updated.water_level == 8.0
  end

  test "get_config/1 returns ratio for water_level" do
    state = base_state(water_level_ratio: 0.75)

    assert Ocean.get_config(state) == %{
             wave_strength: 1.0,
             damping: 0.95,
             water_level: 0.75
           }
  end

  test "now_playing_meta/1 summarizes settings and interaction hint" do
    assert Ocean.now_playing_meta(%{wave_strength: 1.5, damping: 0.9, water_level: 0.6}) == [
             "strength 1.50",
             "damping 0.90",
             "level 60%",
             "Press panels for waves"
           ]
  end

  test "compatible?/0 requires gapped panels" do
    assert Ocean.compatible?()
  end
end
