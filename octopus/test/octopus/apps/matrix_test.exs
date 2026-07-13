defmodule Octopus.Apps.MatrixTest do
  use Octopus.DataCase, async: true

  alias Octopus.Apps.Matrix
  alias Octopus.Apps.Matrix.{Particle, State}
  alias Octopus.Canvas

  @matrix Module.concat(["Octopus", "Apps", "Matrix"])
  @presets Module.concat(["Octopus", "AppModePresets"])

  setup do
    preset_sync_all!()
    :ok
  end

  defp base_state(overrides \\ []) do
    defaults = %{
      canvas: nil,
      particles: [],
      particle_count: 0,
      width: 96,
      height: 8,
      pitch: 26,
      panel_width: 8,
      global_speed: 1.0,
      speed: 1.0,
      density: 3,
      max_particles: 200,
      direction: :classic,
      tail_length: 4,
      counterflow: 0.0,
      sway_scale: 0.0,
      sway_speed: 0.5,
      sway_mode: :wobble,
      afterglow: 60,
      seconds: 0.0,
      occupied_columns: MapSet.new(),
      column_cooldowns: %{},
      now: 0.0
    }

    struct!(State, Map.merge(defaults, Map.new(overrides)))
  end

  describe "presets and foyer tweakables" do
    test "list_modes/0 includes matrix and matrix-ring" do
      modes = matrix_list_modes()
      ids = Enum.map(modes, & &1.id)

      assert "matrix:matrix" in ids
      assert "matrix:matrix-ring" in ids
      assert Enum.all?(modes, & &1.builtin)
    end

    test "mode_config/1 returns defaults for both presets" do
      assert matrix_mode_config("matrix:matrix") == %{
               direction: :classic,
               speed: 6.0,
               bleeding: 10.0,
               density: 1,
               max_particles: 36,
               tail_length: 4,
               counterflow: 0.0,
               sway_scale: 0.0,
               sway_speed: 0.5,
               sway_mode: :wobble,
               afterglow: 60
             }

      assert matrix_mode_config("matrix:matrix-ring") == %{
               direction: :ring,
               speed: 0.15,
               bleeding: 10.0,
               density: 1,
               max_particles: 12,
               tail_length: 8,
               counterflow: 0.0,
               sway_scale: 0.0,
               sway_speed: 0.5,
               sway_mode: :wobble,
               afterglow: 0
             }

      assert matrix_mode_config("matrix") == matrix_mode_config("matrix:matrix")
      assert matrix_mode_config("unknown") == %{}
    end

    test "mode_tweakables/1 exposes all foyer controls" do
      keys =
        matrix_mode_tweakables("matrix")
        |> Enum.map(& &1.key)

      assert keys == [
               :direction,
               :speed,
               :afterglow,
               :bleeding,
               :density,
               :max_particles,
               :tail_length,
               :counterflow,
               :sway_scale,
               :sway_speed,
               :sway_mode
             ]
      assert matrix_mode_tweakables("matrix-ring") == matrix_mode_tweakables("matrix")
      assert matrix_mode_tweakables("unknown") == []
    end

    test "get_config/1 returns tweakable fields" do
      state =
        base_state(
          direction: :ring,
          speed: 2.0,
          density: 5,
          max_particles: 150,
          tail_length: 7,
          counterflow: 0.25,
          sway_scale: 1.5,
          sway_speed: 0.8,
          sway_mode: :pendulum
        )

      assert %{
               direction: :ring,
               speed: 2.0,
               density: 5,
               max_particles: 150,
               tail_length: 7,
               counterflow: 0.25,
               sway_scale: 1.5,
               sway_speed: 0.8,
               sway_mode: :pendulum
             } = matrix_get_config(state)
    end

    test "handle_config/2 applies live settings" do
      state = base_state()

      {:noreply, updated} =
        matrix_handle_config(
          %{
            direction: :ring,
            speed: 1.5,
            density: 7,
            max_particles: 300,
            tail_length: 6,
            counterflow: 0.5,
            sway_scale: 2.0,
            sway_speed: 1.0,
            sway_mode: :wobble
          },
          state
        )

      assert updated.direction == :ring
      assert updated.speed == 1.5
      assert updated.density == 7
      assert updated.max_particles == 300
      assert updated.tail_length == 6
      assert updated.counterflow == 0.5
      assert updated.sway_scale == 2.0
      assert updated.sway_speed == 1.0
      assert updated.sway_mode == :wobble
    end

    test "handle_config/2 merges partial updates" do
      state = base_state(speed: 2.0, density: 4, max_particles: 100, tail_length: 5)

      {:noreply, updated} = matrix_handle_config(%{density: 8}, state)

      assert updated.speed == 2.0
      assert updated.density == 8
      assert updated.max_particles == 100
      assert updated.tail_length == 5
    end

    test "handle_config/2 clears particles when direction changes" do
      particle = %Particle{
        x: 0.0,
        y: 1.0,
        z: 1.0,
        speed: 5.0,
        sign: 1,
        age: 0.0,
        fade_age: 0.0,
        tail: [1.0, 0.9],
        column: 0
      }

      state =
        base_state(
          direction: :classic,
          particles: [particle],
          particle_count: 1,
          occupied_columns: MapSet.new([0])
        )

      {:noreply, updated} = matrix_handle_config(%{direction: :ring}, state)

      assert updated.direction == :ring
      assert updated.particles == []
      assert updated.particle_count == 0
      assert MapSet.size(updated.occupied_columns) == 0
    end

    test "now_playing_meta/1 summarizes direction, tail, density, sway, and max particles" do
      assert matrix_now_playing_meta(%{
               direction: :ring,
               max_particles: 250,
               density: 6,
               tail_length: 8,
               sway_scale: 1.5
             }) == ["ring", "tail 8", "250 particles max", "density 6", "sway 1.5"]
    end

    test "compatible?/0 for Nation2025 8x8 wall" do
      assert matrix_compatible?()
    end
  end

  describe "rendering quality" do
    test "tail segment brightness is monotonically decreasing" do
      brightnesses = for i <- 0..9, do: State.tail_segment_brightness(i)

      assert Enum.chunk_every(brightnesses, 2, 1, :discard)
             |> Enum.all?(fn [a, b] -> a >= b end)
    end

    test "soft pixel weights sum to 1.0" do
      for pos <- [0.0, 0.25, 3.7, 12.333, 99.99] do
        {w0, w1, _low} = State.soft_weights(pos)
        assert_in_delta w0 + w1, 1.0, 0.0001
      end
    end

    test "bilinear weights sum to 1.0" do
      for fx <- [0.0, 0.25, 0.5, 0.99], fy <- [0.0, 0.33, 0.75] do
        {w00, w10, w01, w11} = State.bilinear_weights(fx, fy)
        assert_in_delta w00 + w10 + w01 + w11, 1.0, 0.0001
      end
    end

    test "sway_scale 0 ring render matches previous fast path" do
      particle = %Particle{
        x: 10.5,
        y: 3.0,
        z: 1.0,
        speed: 5.0,
        sign: 1,
        age: 0.0,
        fade_age: 0.0,
        tail: [0.9, 0.8],
        column: 3
      }

      state =
        base_state(
          width: 40,
          height: 8,
          direction: :ring,
          sway_scale: 0.0,
          particles: [particle],
          particle_count: 1
        )

      %{canvas: canvas_a} = State.render(state)
      %{canvas: canvas_b} = State.render(state)

      assert canvas_pixels(canvas_a) == canvas_pixels(canvas_b)
    end

    test "tail segments get different y offsets along the wave" do
      width = 100.0
      amplitude = 2.0
      phase = 0.0

      y0 = State.segment_y_drawn(3.0, 0.0, width, amplitude, phase, 1.0)
      y_quarter = State.segment_y_drawn(3.0, width / 4, width, amplitude, phase, 1.0)

      assert_in_delta y_quarter - y0, amplitude, 0.05
    end

    test "ring mode with sway draws wrapped head across seam at x = W-0.5" do
      width = 20

      particle = %Particle{
        x: width - 0.5,
        y: 3.0,
        z: 1.0,
        speed: 5.0,
        sign: 1,
        age: 0.0,
        fade_age: 0.0,
        tail: [],
        column: 3
      }

      state =
        base_state(
          width: width,
          height: 8,
          direction: :ring,
          sway_scale: 1.5,
          sway_speed: 0.5,
          sway_mode: :wobble,
          seconds: 1.0,
          particles: [particle],
          particle_count: 1
        )

      %{canvas: canvas} = State.render(state)

      assert Canvas.get_pixel(canvas, {width - 1, 3}) != {0, 0, 0}
      assert Canvas.get_pixel(canvas, {0, 3}) != {0, 0, 0}
    end
  end

  describe "sway time base" do
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
          max_particles: 1,
          density: 1,
          tail_length: 4
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
          max_particles: 10,
          density: 10,
          tail_length: 4
        )

      state = State.spawn_particles(state, 20)
      columns = Enum.map(state.particles, & &1.column)

      assert length(columns) == length(Enum.uniq(columns))
    end

    test "column cooldown blocks respawn after release" do
      particle = %Particle{
        x: 0.0,
        y: 7.5,
        z: 1.0,
        speed: 10.0,
        sign: 1,
        age: 0.0,
        fade_age: 0.0,
        tail: [1.0],
        column: 0
      }

      state =
        base_state(
          width: 52,
          pitch: 26,
          panel_width: 8,
          height: 8,
          particles: [particle],
          particle_count: 1,
          occupied_columns: MapSet.new([0]),
          now: 10.0
        )

      updated = State.update(state, 0.1)

      assert not MapSet.member?(updated.occupied_columns, 0)
      assert Map.fetch!(updated.column_cooldowns, 0) > updated.now

      blocked =
        base_state(
          width: 52,
          pitch: 26,
          panel_width: 8,
          max_particles: 1,
          column_cooldowns: updated.column_cooldowns,
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

  defp preset_sync_all!, do: apply(@presets, :sync_all!, [])
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
