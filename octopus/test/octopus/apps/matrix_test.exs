defmodule Octopus.Apps.MatrixTest do
  use ExUnit.Case, async: true

  alias Octopus.Apps.Matrix
  alias Octopus.Apps.Matrix.State

  defp base_state(overrides \\ []) do
    defaults = %{
      canvas: nil,
      particles: [],
      width: 96,
      height: 8,
      global_speed: 1.0,
      speed: 1.0,
      density: 3,
      max_particles: 200
    }

    struct!(State, Map.merge(defaults, Map.new(overrides)))
  end

  test "list_modes/0 includes matrix mode" do
    [mode] = Matrix.list_modes()
    assert mode.id == "matrix"
    assert mode.builtin == true
  end

  test "mode_config/1 returns defaults" do
    assert Matrix.mode_config("matrix") == %{speed: 1.0, density: 3, max_particles: 200}
    assert Matrix.mode_config("unknown") == %{}
  end

  test "mode_tweakables/1 exposes speed, density, max_particles" do
    keys =
      Matrix.mode_tweakables("matrix")
      |> Enum.map(& &1.key)

    assert keys == [:speed, :density, :max_particles]
    assert Matrix.mode_tweakables("unknown") == []
  end

  test "get_config/1 returns tweakable fields" do
    state = base_state(speed: 2.0, density: 5, max_particles: 150)

    assert Matrix.get_config(state) == %{
             speed: 2.0,
             density: 5,
             max_particles: 150
           }
  end

  test "handle_config/2 applies speed, density, and max_particles live" do
    state = base_state()

    {:noreply, updated} =
      Matrix.handle_config(%{speed: 1.5, density: 7, max_particles: 300}, state)

    assert updated.speed == 1.5
    assert updated.density == 7
    assert updated.max_particles == 300
  end

  test "handle_config/2 merges partial updates" do
    state = base_state(speed: 2.0, density: 4, max_particles: 100)

    {:noreply, updated} = Matrix.handle_config(%{density: 8}, state)

    assert updated.speed == 2.0
    assert updated.density == 8
    assert updated.max_particles == 100
  end

  test "now_playing_meta/1 summarizes density and max particles" do
    assert Matrix.now_playing_meta(%{max_particles: 250, density: 6}) == [
             "250 particles max",
             "density 6"
           ]
  end

  test "compatible?/0 for Nation2025 8x8 wall" do
    assert Matrix.compatible?()
  end
end
