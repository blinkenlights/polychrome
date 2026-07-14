defmodule Octopus.Apps.PerlinNoiseTest do
  use Octopus.DataCase, async: false

  alias Octopus.Apps.PerlinNoise
  alias Octopus.Canvas
  alias Octopus.Installation

  @perlin_noise PerlinNoise

  setup do
    original_installation = Application.get_env(:octopus, :installation)

    on_exit(fn ->
      Application.put_env(:octopus, :installation, original_installation)
    end)

    %{original_installation: original_installation}
  end

  test "list_modes/0 includes perlin mode" do
    [mode] = perlin_noise_list_modes()
    assert mode.id == "perlinnoise:perlin"
    assert mode.builtin == true
  end

  test "mode_config/1 returns defaults" do
    defaults = %{
      scale: PerlinNoise.default_scale(),
      octaves: 4,
      persistence: 0.5,
      speed: 1.0,
      seed: 42,
      contrast: 3.0
    }

    assert perlin_noise_mode_config("perlinnoise:perlin") == defaults
    assert perlin_noise_mode_config("perlin") == defaults
    assert perlin_noise_mode_config("unknown") == %{}
  end

  test "default_scale/0 targets ~2.5 noise units per panel width" do
    assert PerlinNoise.default_scale() == 2.5 / Installation.panel_width()
  end

  test "mode_tweakables/1 exposes foyer live controls" do
    keys =
      perlin_noise_mode_tweakables("perlin")
      |> Enum.map(& &1.key)

    assert keys == [:contrast, :scale, :speed, :seed]
  end

  test "config_schema/0 includes advanced settings for full editor" do
    keys = apply(@perlin_noise, :config_schema, []) |> Map.keys() |> Enum.sort()
    assert keys == Enum.sort([:scale, :octaves, :persistence, :speed, :seed, :contrast])
  end

  test "handle_config/2 applies settings live" do
    state = %{
      time: 0.0,
      scale: PerlinNoise.default_scale(),
      octaves: 4,
      persistence: 0.5,
      speed: 1.0,
      seed: 42,
      contrast: 3.0
    }

    {:noreply, updated} =
      perlin_noise_handle_config(
        %{scale: 0.2, octaves: 6, speed: 2.0, seed: 99, contrast: 5.0},
        state
      )

    assert updated.scale == 0.2
    assert updated.octaves == 6
    assert updated.speed == 2.0
    assert updated.seed == 99
    assert updated.contrast == 5.0
    assert updated.persistence == 0.5
  end

  test "now_playing_meta/1 summarizes key settings" do
    assert perlin_noise_now_playing_meta(%{
             scale: 0.15,
             speed: 1.5,
             contrast: 4.0
           }) == [
             "contrast 4.00",
             "detail 0.15",
             "speed 1.50"
           ]
  end

  test "compatible?/0" do
    assert perlin_noise_compatible?()
  end

  test "circular ring sampling is seamless at canvas wrap", %{original_installation: _} do
    Application.put_env(:octopus, :installation, Octopus.Installation.Nation2026)

    width = Installation.num_panels() * Installation.panel_width()
    height = Installation.panel_height()

    state = %{
      time: 0.0,
      scale: PerlinNoise.default_scale(),
      octaves: 4,
      persistence: 0.5,
      speed: 1.0,
      seed: 42,
      contrast: 3.0
    }

    canvas = PerlinNoise.render_canvas(width, height, state)

    left = Canvas.get_pixel(canvas, {0, 0})
    right = Canvas.get_pixel(canvas, {width - 1, 0})
    diff = abs(left - right)

    assert diff < 95
  end

  defp perlin_noise_list_modes, do: apply(@perlin_noise, :list_modes, [])
  defp perlin_noise_mode_config(mode_id), do: apply(@perlin_noise, :mode_config, [mode_id])
  defp perlin_noise_mode_tweakables(mode_id), do: apply(@perlin_noise, :mode_tweakables, [mode_id])

  defp perlin_noise_handle_config(config, state),
    do: apply(@perlin_noise, :handle_config, [config, state])

  defp perlin_noise_now_playing_meta(config), do: apply(@perlin_noise, :now_playing_meta, [config])
  defp perlin_noise_compatible?, do: apply(@perlin_noise, :compatible?, [])
end
