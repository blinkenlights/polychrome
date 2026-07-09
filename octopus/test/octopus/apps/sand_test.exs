defmodule Octopus.Apps.SandTest do
  use Octopus.DataCase, async: true

  alias Octopus.AppModePresets
  alias Octopus.Apps.Sand
  alias Octopus.Apps.Sand.State

  setup do
    AppModePresets.sync_all!()
    :ok
  end

  defp base_state(overrides) do
    defaults = %{
      panels: %{},
      spawn_rate: 0.25,
      button_force: 40,
      auto_drain: true,
      color_mode: :rainbow
    }

    struct!(State, Map.merge(defaults, Map.new(overrides)))
  end

  test "list_modes/0 includes sand mode" do
    [mode] = Sand.list_modes()
    assert mode.id == "sand:sand"
    assert mode.builtin == true
  end

  test "mode_config/1 returns defaults" do
    defaults = %{
      spawn_rate: 0.25,
      button_force: 40,
      auto_drain: true,
      color_mode: :rainbow
    }

    assert Sand.mode_config("sand:sand") == defaults
    assert Sand.mode_config("sand") == defaults
    assert Sand.mode_config("unknown") == %{}
  end

  test "mode_tweakables/1 exposes spawn_rate, button_force, auto_drain, color_mode" do
    keys =
      Sand.mode_tweakables("sand")
      |> Enum.map(& &1.key)

    assert keys == [:spawn_rate, :button_force, :auto_drain, :color_mode]
  end

  test "handle_config/2 applies partial updates without clearing panels" do
    state = base_state(panels: %{0 => :panel})

    {:noreply, updated} = Sand.handle_config(%{spawn_rate: 0.5}, state)

    assert updated.spawn_rate == 0.5
    assert updated.button_force == 40
    assert updated.panels == %{0 => :panel}
  end

  test "get_config/1 returns tweakable values" do
    state = base_state(spawn_rate: 0.4, button_force: 55, auto_drain: false, color_mode: :warm)

    assert Sand.get_config(state) == %{
             spawn_rate: 0.4,
             button_force: 55,
             auto_drain: false,
             color_mode: :warm
           }
  end

  test "now_playing_meta/1 summarizes settings and interaction hint" do
    assert Sand.now_playing_meta(%{
             spawn_rate: 0.25,
             button_force: 40,
             auto_drain: true,
             color_mode: :rainbow
           }) == [
             "spawn 25%",
             "blast 40",
             "auto-drain on",
             "rainbow",
             "Press buttons to explode"
           ]
  end

  test "compatible?/0 requires one button per panel" do
    assert Sand.compatible?()
  end
end
