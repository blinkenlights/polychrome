defmodule Octopus.Apps.SandTest do
  use Octopus.DataCase, async: true

  alias Octopus.Apps.Sand
  alias Octopus.Apps.Sand.State

  @sand Sand
  @presets Module.concat(["Octopus", "AppModePresets"])

  setup do
    preset_sync_all!()
    :ok
  end

  defp base_state(overrides) do
    defaults = Sand.legacy_mode_config("sand")

    struct!(State, Map.merge(defaults, Map.new(overrides)))
  end

  test "list_modes/0 includes all builtin sand presets" do
    modes = sand_list_modes()
    ids = Enum.map(modes, & &1.id)

    assert "sand:sand" in ids
    assert "sand:dunes" in ids
    assert "sand:hourglass" in ids
    assert "sand:cascade" in ids
    assert "sand:aurora" in ids
    assert "sand:storm" in ids
    assert Enum.all?(modes, & &1.builtin)
  end

  test "mode_config/1 returns defaults for classic sand" do
    defaults = Sand.legacy_mode_config("sand")

    assert sand_mode_config("sand:sand") == defaults
    assert sand_mode_config("sand") == defaults
    assert sand_mode_config("unknown") == %{}
  end

  test "mode_config/1 returns preset-specific values" do
    hourglass = sand_mode_config("sand:hourglass")
    assert hourglass.spawn_shape == :fountain
    assert hourglass.spawn_rate == 0.08
    assert hourglass.plug_drain == true

    storm = sand_mode_config("sand:storm")
    assert storm.wind_auto == true
    assert storm.overflow_auto == true
  end

  test "mode_tweakables/1 exposes expected keys without button_force" do
    keys =
      sand_mode_tweakables("sand")
      |> Enum.map(& &1.key)

    assert :spawn_rate in keys
    assert :spawn_shape in keys
    assert :wind_strength in keys
    assert :wind_auto in keys
    assert :bleeding in keys
    assert :overflow_mode in keys
    assert :overflow_auto in keys
    assert :plug_drain in keys
    assert :color_mix in keys
    refute :button_force in keys
  end

  test "summary_for_preset/1 formats preset summary" do
    summary =
      Sand.summary_for_preset(%{
        config: %{
          spawn_rate: 0.08,
          wind_auto: true,
          overflow_mode: :waterfall,
          color_mix: 0.7,
          plug_drain: true,
          plug_drain_interval: 12.0
        }
      })

    assert summary =~ "spawn 8%"
    assert summary =~ "wind auto"
    assert summary =~ "overflow waterfall"
    assert summary =~ "mix 70%"
    assert summary =~ "plug 12.0s"
  end

  test "handle_config/2 applies partial updates without clearing panels" do
    state = base_state(panels: %{0 => :panel})

    {:noreply, updated} = sand_handle_config(%{spawn_rate: 0.5}, state)

    assert updated.spawn_rate == 0.5
    assert updated.spawn_shape == :rain
    assert updated.panels == %{0 => :panel}
  end

  test "handle_config/2 disables overflow_auto when overflow_mode is set" do
    state = base_state(overflow_auto: true)

    {:noreply, updated} =
      sand_handle_config(%{overflow_mode: :waterfall}, state)

    assert updated.overflow_mode == :waterfall
    assert updated.overflow_auto == false
  end

  test "get_config/1 returns tweakable values with display scaling" do
    state =
      base_state(
        spawn_rate: 0.4,
        color_mode: :warm,
        color_mix: 0.5,
        collapse_sensitivity: 0.25,
        supersample: 2,
        gravity: 0.1,
        overflow_auto: true,
        runtime_overflow_mode: :abyss
      )

    assert %{
             spawn_rate: 0.4,
             color_mode: :warm,
             color_mix: 50.0,
             collapse_sensitivity: 25.0,
             supersample: 2,
             gravity: 0.1,
             overflow_mode: :abyss,
             overflow_auto: true
           } = sand_get_config(state)
  end

  test "now_playing_meta/1 summarizes settings" do
    meta =
      sand_now_playing_meta(%{
        spawn_rate: 0.25,
        spawn_shape: :rain,
        wind_auto: false,
        wind_strength: 0.8,
        overflow_mode: :block,
        overflow_auto: false,
        color_mix: 0.0,
        gravity: 0.35
      })

    assert Enum.any?(meta, &String.contains?(&1, "spawn 25%"))
    assert Enum.any?(meta, &String.contains?(&1, "wind 0.8"))
    assert Enum.any?(meta, &String.contains?(&1, "overflow block"))
  end

  test "compatible?/0 allows panels without buttons or one button per panel" do
    assert sand_compatible?()

    with_installation(Octopus.Installation.Nation2026, fn ->
      assert sand_compatible?()
    end)

    with_installation(Octopus.Installation.Nation2025, fn ->
      assert sand_compatible?()
    end)
  end

  defp with_installation(installation, fun) do
    previous = Application.get_env(:octopus, :installation)
    Application.put_env(:octopus, :installation, installation)

    try do
      fun.()
    after
      Application.put_env(:octopus, :installation, previous)
    end
  end

  defp preset_sync_all!, do: apply(@presets, :sync_all!, [])
  defp sand_list_modes, do: apply(@sand, :list_modes, [])
  defp sand_mode_config(mode_id), do: apply(@sand, :mode_config, [mode_id])
  defp sand_mode_tweakables(mode_id), do: apply(@sand, :mode_tweakables, [mode_id])
  defp sand_handle_config(config, state), do: apply(@sand, :handle_config, [config, state])
  defp sand_get_config(state), do: apply(@sand, :get_config, [state])
  defp sand_now_playing_meta(config), do: apply(@sand, :now_playing_meta, [config])
  defp sand_compatible?, do: apply(@sand, :compatible?, [])
end
