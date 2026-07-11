defmodule Octopus.Apps.SandTest do
  use Octopus.DataCase, async: true

  alias Octopus.Apps.Sand.State
  alias Octopus.Apps.Sand.Sim

  @sand Module.concat(["Octopus", "Apps", "Sand"])
  @presets Module.concat(["Octopus", "AppModePresets"])
  @default_supersample 4

  setup do
    preset_sync_all!()
    :ok
  end

  defp base_state(overrides) do
    s = @default_supersample

    defaults = %{
      panels: %{},
      spawn_rate: 0.25,
      button_force: 40,
      auto_drain: true,
      color_mode: :rainbow,
      supersample: s,
      gravity: Sim.default_gravity(s)
    }

    struct!(State, Map.merge(defaults, Map.new(overrides)))
  end

  test "list_modes/0 includes sand mode" do
    [mode] = sand_list_modes()
    assert mode.id == "sand:sand"
    assert mode.builtin == true
  end

  test "mode_config/1 returns defaults" do
    s = @default_supersample

    defaults = %{
      spawn_rate: 0.25,
      button_force: 40,
      auto_drain: true,
      color_mode: :rainbow,
      supersample: s,
      gravity: Sim.default_gravity(s)
    }

    assert sand_mode_config("sand:sand") == defaults
    assert sand_mode_config("sand") == defaults
    assert sand_mode_config("unknown") == %{}
  end

  test "mode_tweakables/1 exposes all tweakable keys" do
    keys =
      sand_mode_tweakables("sand")
      |> Enum.map(& &1.key)

    assert keys == [:spawn_rate, :button_force, :auto_drain, :color_mode, :supersample, :gravity]
  end

  test "handle_config/2 applies partial updates without clearing panels" do
    state = base_state(panels: %{0 => :panel})

    {:noreply, updated} = sand_handle_config(%{spawn_rate: 0.5}, state)

    assert updated.spawn_rate == 0.5
    assert updated.button_force == 40
    assert updated.panels == %{0 => :panel}
  end

  test "get_config/1 returns tweakable values" do
    state =
      base_state(
        spawn_rate: 0.4,
        button_force: 55,
        auto_drain: false,
        color_mode: :warm,
        supersample: 2,
        gravity: 0.1
      )

    assert %{
             spawn_rate: 0.4,
             button_force: 55,
             auto_drain: false,
             color_mode: :warm,
             supersample: 2,
             gravity: 0.1
           } = sand_get_config(state)
  end

  test "now_playing_meta/1 summarizes settings and interaction hint" do
    s = @default_supersample
    gravity = Sim.default_gravity(s)

    assert sand_now_playing_meta(%{
             spawn_rate: 0.25,
             button_force: 40,
             auto_drain: true,
             color_mode: :rainbow,
             supersample: s,
             gravity: gravity
           }) == [
             "spawn 25%",
             "blast 40",
             "auto-drain on",
             "rainbow",
             "S=4 grav=#{Float.round(gravity, 2)}",
             "Press buttons to explode"
           ]
  end

  test "compatible?/0 requires one button per panel" do
    assert sand_compatible?()
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
