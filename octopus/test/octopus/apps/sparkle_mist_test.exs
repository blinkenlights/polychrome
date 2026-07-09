defmodule Octopus.Apps.SparkleMistTest do
  use Octopus.DataCase, async: true

  alias Octopus.AppModePresets
  alias Octopus.Apps.SparkleMist
  alias Octopus.Apps.SparkleMist.State

  setup do
    AppModePresets.sync_all!()
    :ok
  end

  defp base_state(overrides) do
    state = %State{
      particles: %{},
      last_update: 0,
      track_registry: %{},
      track_motion: %{},
      last_trickle: %{}
    }

    {:noreply, configured} = SparkleMist.handle_config(SparkleMist.legacy_mode_config("mist"), state)
    struct!(configured, Map.new(overrides))
  end

  test "list_modes/0 includes mist mode" do
    [mode] = SparkleMist.list_modes()
    assert mode.id == "sparklemist:mist"
    assert mode.builtin == true
  end

  test "mode_config/1 returns defaults" do
    defaults = SparkleMist.legacy_mode_config("mist")

    assert SparkleMist.mode_config("sparklemist:mist") == defaults
    assert SparkleMist.mode_config("mist") == defaults
    assert SparkleMist.mode_config("unknown") == %{}
  end

  test "mode_tweakables/1 exposes foyer sliders" do
    keys =
      SparkleMist.mode_tweakables("mist")
      |> Enum.map(& &1.key)

    assert keys == [:foreground_hue, :background_speed, :particle_speed_scale, :background_hue_a]
  end

  test "handle_config/2 applies partial updates without clearing particles" do
    state = base_state(particles: %{0 => :panel})

    {:noreply, updated} = SparkleMist.handle_config(%{foreground_hue: 120}, state)

    assert updated.foreground_hue == 120
    assert updated.background_speed == 5.0
    assert updated.particles == %{0 => :panel}
    assert updated.parsed_expr != nil
  end

  test "get_config/1 returns tweakable values" do
    state =
      base_state(
        foreground_hue: 90,
        background_speed: 3.0,
        particle_speed_scale: 2.0,
        background_hue_a: 180
      )

    assert SparkleMist.get_config(state) == %{
             foreground_hue: 90,
             background_hue_a: 180,
             background_hue_b: 170,
             background_sat_a: 100,
             background_sat_b: 85,
             expr: "noise(sin(x/26-t+y/40),x*0.01,y*0.01)",
             particle_speed_scale: 2.0,
             background_speed: 3.0
           }
  end

  test "now_playing_meta/1 summarizes settings and interaction hint" do
    assert SparkleMist.now_playing_meta(SparkleMist.legacy_mode_config("mist")) == [
             "spark hue 25",
             "mist speed 5.0",
             "intensity 1.0",
             "bg hue 200",
             "Walk the ring for sparkles"
           ]
  end

  test "compatible?/0 requires minimum panel size" do
    assert SparkleMist.compatible?()
  end
end
