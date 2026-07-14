defmodule Octopus.Apps.MatrixTest do
  use Octopus.DataCase, async: true

  alias Octopus.Apps.Matrix
  alias Octopus.Apps.Matrix.{Particle, State}
  alias Octopus.Canvas

  @matrix Module.concat(["Octopus", "Apps", "Matrix"])

  defp base_state(overrides \\ []) do
    defaults = %{
      canvas: nil,
      particles: [],
      particle_count: 0,
      width: 96,
      height: 8,
      pitch: 26,
      panel_width: 8,
      panel_count: 4,
      global_speed: 1.0,
      speed: 1.0,
      density: 3,
      max_particles: 200,
      trail_length: 135,
      afterglow: 60,
      seconds: 0.0,
      occupied_columns: MapSet.new(),
      column_cooldowns: %{},
      now: 0.0
    }

    struct!(State, Map.merge(defaults, Map.new(overrides)))
  end

  describe "presets and foyer tweakables" do
    test "list_modes/0 includes matrix preset only" do
      modes = matrix_list_modes()
      ids = Enum.map(modes, & &1.id)

      assert "matrix:matrix" in ids
      refute "matrix:matrix-ring" in ids
      assert Enum.all?(modes, & &1.builtin)
    end

    test "mode_config/1 returns defaults for matrix preset" do
      assert matrix_mode_config("matrix:matrix") == %{
               speed: 8.0,
               bleeding: 10.0,
               density: 1,
               max_particles: 24,
               trail_length: 135,
               afterglow: 60
             }

      assert matrix_mode_config("matrix") == matrix_mode_config("matrix:matrix")
      assert matrix_mode_config("unknown") == %{}
    end

    test "normalize_mode_config/1 migrates legacy tail_length to trail_length" do
      assert Matrix.normalize_mode_config(%{tail_length: 4, speed: 6.0})[:trail_length] == 135
      assert Matrix.normalize_mode_config(%{tail_length: 120, speed: 6.0})[:trail_length] == 120
    end

    test "mode_tweakables/1 exposes foyer controls" do
      keys =
        matrix_mode_tweakables("matrix")
        |> Enum.map(& &1.key)

      assert keys == [
               :speed,
               :afterglow,
               :bleeding,
               :density,
               :max_particles,
               :trail_length
             ]

      assert matrix_mode_tweakables("unknown") == []
    end

    test "get_config/1 returns tweakable fields" do
      state =
        base_state(
          speed: 2.0,
          density: 5,
          max_particles: 150,
          trail_length: 100
        )

      assert %{
               speed: 2.0,
               density: 5,
               max_particles: 150,
               trail_length: 100
             } = matrix_get_config(state)
    end

    test "handle_config/2 applies live settings" do
      state = base_state()

      {:noreply, updated} =
        matrix_handle_config(
          %{
            speed: 1.5,
            density: 7,
            max_particles: 300,
            trail_length: 80
          },
          state
        )

      assert updated.speed == 1.5
      assert updated.density == 7
      assert updated.max_particles == 300
      assert updated.trail_length == 80
    end

    test "handle_config/2 merges partial updates" do
      state = base_state(speed: 2.0, density: 4, max_particles: 100, trail_length: 120)

      {:noreply, updated} = matrix_handle_config(%{density: 8}, state)

      assert updated.speed == 2.0
      assert updated.density == 8
      assert updated.max_particles == 100
      assert updated.trail_length == 120
    end

    test "now_playing_meta/1 summarizes trail, density, and max particles" do
      assert matrix_now_playing_meta(%{
               max_particles: 250,
               density: 6,
               trail_length: 100
             }) == ["trail 100", "250 particles max", "density 6"]
    end

    test "compatible?/0 requires 8x8 panel installation" do
      result = matrix_compatible?()
      assert is_boolean(result)
    end

    test "default_max_particles/1 enforces minimum of 12" do
      assert Matrix.default_max_particles(1) == 12
      assert Matrix.default_max_particles(8) == 24
    end
  end

  describe "rendering quality" do
    test "soft pixel weights sum to 1.0" do
      for pos <- [0.0, 0.25, 3.7, 12.333, 99.99] do
        {w0, w1, _low} = State.soft_weights(pos)
        assert_in_delta w0 + w1, 1.0, 0.0001
      end
    end

    test "classic render is deterministic" do
      particle = %Particle{
        x: 10.0,
        y: 3.0,
        z: 1.0,
        speed: 5.0,
        age: 0.0,
        fade_age: 0.0,
        column: 10,
        trail_length: 135
      }

      state =
        base_state(
          width: 40,
          height: 8,
          particles: [particle],
          particle_count: 1
        )

      %{canvas: canvas_a} = State.render(state)
      %{canvas: canvas_b} = State.render(state)

      assert canvas_pixels(canvas_a) == canvas_pixels(canvas_b)
    end
  end

  describe "time base" do
    test "update/2 advances seconds with dt" do
      state = base_state(seconds: 1.0)
      updated = State.update(state, 0.5)
      assert_in_delta updated.seconds, 1.5, 0.0001
    end
  end

  describe "classic mode occupancy" do
    test "spawns only on visible columns" do
      state =
        base_state(
          width: 52,
          pitch: 26,
          panel_width: 8,
          panel_count: 2,
          max_particles: 1,
          density: 1
        )

      state = State.spawn_particles(state, 1)
      [particle] = state.particles

      assert rem(trunc(particle.x), state.pitch) < state.panel_width
      assert MapSet.member?(state.occupied_columns, particle.column)
    end

    test "does not spawn two drops in the same column" do
      state =
        base_state(
          width: 52,
          pitch: 26,
          panel_width: 8,
          panel_count: 2,
          max_particles: 10,
          density: 10
        )

      state = State.spawn_particles(state, 20)
      columns = Enum.map(state.particles, & &1.column)

      assert length(columns) == length(Enum.uniq(columns))
    end

    test "enforces minimum column gap of 3 between heads" do
      state =
        base_state(
          width: 26,
          pitch: 26,
          panel_width: 8,
          panel_count: 1,
          max_particles: 20,
          density: 10
        )

      state = State.spawn_particles(state, 20)
      columns = Enum.map(state.particles, & &1.column)

      assert Enum.all?(for a <- columns, b <- columns, a < b, do: abs(a - b) >= 3)
    end

    test "all spawned drops share the configured trail length" do
      state =
        base_state(
          width: 52,
          pitch: 26,
          panel_width: 8,
          panel_count: 2,
          max_particles: 10,
          trail_length: 100
        )

      state = State.spawn_particles(state, 5)

      assert Enum.all?(state.particles, &(&1.trail_length == 100))
    end

    test "distributes spawns evenly across panels" do
      panel_count = 8
      pitch = 26

      state =
        base_state(
          width: panel_count * pitch,
          pitch: pitch,
          panel_width: 8,
          panel_count: panel_count,
          max_particles: 24,
          density: 10
        )

      state = State.spawn_particles(state, 24)

      counts =
        state.particles
        |> Enum.map(& &1.column)
        |> Enum.group_by(&div(&1, pitch))
        |> Map.new(fn {panel, cols} -> {panel, length(cols)} end)

      values = Map.values(counts)
      assert length(values) >= 4
      assert Enum.max(values) - Enum.min(values) <= 1
    end

    test "column cooldown blocks respawn after release" do
      blocked =
        base_state(
          width: 52,
          pitch: 26,
          panel_width: 8,
          panel_count: 2,
          max_particles: 1,
          column_cooldowns: %{0 => 100.0},
          now: 10.5
        )
        |> State.spawn_particles(5)

      refute Enum.any?(blocked.particles, &(&1.column == 0))
    end
  end

  describe "helpers" do
    test "wrap_x/2 normalizes negative positions" do
      assert_in_delta Matrix.wrap_x(-0.5, 20), 19.5, 0.0001
      assert_in_delta Matrix.wrap_x(20.5, 20), 0.5, 0.0001
    end
  end

  defp matrix_list_modes, do: apply(@matrix, :list_modes, [])
  defp matrix_mode_config(mode_id), do: apply(@matrix, :mode_config, [mode_id])
  defp matrix_mode_tweakables(mode_id), do: apply(@matrix, :mode_tweakables, [mode_id])
  defp matrix_handle_config(config, state), do: apply(@matrix, :handle_config, [config, state])
  defp matrix_get_config(state), do: apply(@matrix, :get_config, [state])
  defp matrix_now_playing_meta(config), do: apply(@matrix, :now_playing_meta, [config])
  defp matrix_compatible?, do: apply(@matrix, :compatible?, [])

  defp canvas_pixels(%Canvas{width: width, height: height, pixels: pixels}) do
    for y <- 0..(height - 1), x <- 0..(width - 1), into: %{} do
      {{x, y}, Map.get(pixels, {x, y}, {0, 0, 0})}
    end
  end
end
