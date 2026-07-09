defmodule Octopus.Apps.PerlinNoiseTest do
  use Octopus.DataCase, async: true

  @perlin_noise Module.concat(["Octopus", "Apps", "PerlinNoise"])
  @presets Module.concat(["Octopus", "AppModePresets"])

  setup do
    preset_sync_all!()
    :ok
  end

  test "list_modes/0 includes perlin mode" do
    [mode] = perlin_noise_list_modes()
    assert mode.id == "perlinnoise:perlin"
    assert mode.builtin == true
  end

  test "mode_config/1 returns defaults" do
    defaults = %{
      scale: 0.1,
      octaves: 4,
      persistence: 0.5,
      speed: 1.0,
      seed: 42
    }

    assert perlin_noise_mode_config("perlinnoise:perlin") == defaults
    assert perlin_noise_mode_config("perlin") == defaults
    assert perlin_noise_mode_config("unknown") == %{}
  end

  test "mode_tweakables/1 exposes noise settings" do
    keys =
      perlin_noise_mode_tweakables("perlin")
      |> Enum.map(& &1.key)

    assert keys == [:scale, :octaves, :persistence, :speed, :seed]
  end

  test "handle_config/2 applies settings live" do
    state = %{
      time: 0.0,
      scale: 0.1,
      octaves: 4,
      persistence: 0.5,
      speed: 1.0,
      seed: 42
    }

    {:noreply, updated} =
      perlin_noise_handle_config(%{scale: 0.2, octaves: 6, speed: 2.0, seed: 99}, state)

    assert updated.scale == 0.2
    assert updated.octaves == 6
    assert updated.speed == 2.0
    assert updated.seed == 99
    assert updated.persistence == 0.5
  end

  test "now_playing_meta/1 summarizes key settings" do
    assert perlin_noise_now_playing_meta(%{scale: 0.15, octaves: 5, speed: 1.5}) == [
             "scale 0.15",
             "5 octaves",
             "speed 1.50"
           ]
  end

  test "compatible?/0" do
    assert perlin_noise_compatible?()
  end

  defp preset_sync_all!, do: apply(@presets, :sync_all!, [])
  defp perlin_noise_list_modes, do: apply(@perlin_noise, :list_modes, [])
  defp perlin_noise_mode_config(mode_id), do: apply(@perlin_noise, :mode_config, [mode_id])
  defp perlin_noise_mode_tweakables(mode_id), do: apply(@perlin_noise, :mode_tweakables, [mode_id])
  defp perlin_noise_handle_config(config, state), do: apply(@perlin_noise, :handle_config, [config, state])
  defp perlin_noise_now_playing_meta(config), do: apply(@perlin_noise, :now_playing_meta, [config])
  defp perlin_noise_compatible?, do: apply(@perlin_noise, :compatible?, [])
end
