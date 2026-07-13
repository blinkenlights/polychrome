defmodule Octopus.Apps.Matrix do
  use Octopus.App, category: :animation

  @mode_presets Module.concat(["Octopus", "AppModePresets"])

  @shimmer_chance 0.03

  defmodule Particle do
    defstruct [:x, :y, :z, :speed, :sign, :age, :fade_age, :tail, :column, :columns_left, :trail_length]
  end

  defmodule State do
    alias Octopus.Apps.Matrix, as: Matrix
    alias Octopus.Canvas
    alias Octopus.Sway

    @head_color {160, 255, 160}
    @tail_base {40, 255, 70}
    @tail_brightness_base 0.75
    @tail_decay 0.62
    @fade_duration 0.5
    @classic_speed 1.0
    @trail_brightness 0.55
    @trail_gap_chance 0.35
    # Trail length is measured in cells behind the head (not time): each drop keeps
    # its most recent N deposited cells lit, N random in this range.
    @trail_length_min 100
    @trail_length_max 270
    # Extra factor on how long residue lingers before it is pruned.
    @trail_hold 3.0
    # Random per-cell brightness range for the green trail (varied, not uniform).
    @residue_bright_min 0.4
    @residue_bright_max 1.0
    # Very short ease-in of the white head as it enters each new cell.
    @head_ease_frac 0.25
    @spawn_stagger_min 2.0
    @spawn_stagger_max 10.0
    @column_cooldown_min 0.8
    @column_cooldown_span 4.0
    # A single drop snakes down this many columns (left→right) before it dies.
    @snake_columns_min 1
    @snake_columns_max 5
    # Tiny per-drop variance on the head fall speed (±fraction of @classic_speed).
    @classic_speed_jitter 0.08

    defstruct [
      :canvas,
      :particles,
      :particle_count,
      :width,
      :height,
      :pitch,
      :panel_width,
      :global_speed,
      :speed,
      :density,
      :max_particles,
      :direction,
      :tail_length,
      :counterflow,
      :sway_scale,
      :sway_speed,
      :sway_mode,
      :afterglow,
      :seconds,
      :occupied_columns,
      :column_cooldowns,
      :residue,
      :now
    ]

    def spawn_particles(%State{} = state, amount) do
      Enum.reduce(1..amount, state, fn _, acc ->
        spawn_one(acc)
      end)
    end

    defp spawn_one(%State{particle_count: count, max_particles: max} = state)
         when count >= max,
         do: state

    defp spawn_one(%State{direction: :classic} = state) do
      case pick_classic_column(state) do
        nil -> state
        column -> insert_particle(state, new_classic_particle(state, column))
      end
    end

    defp spawn_one(%State{direction: :ring} = state) do
      case pick_ring_spawn(state) do
        nil -> state
        {x, lane, sign} -> insert_particle(state, new_ring_particle(state, x, lane, sign))
      end
    end

    def update(%State{} = state, dt) do
      now = monotonic_now()
      seconds = (state.seconds || 0.0) + dt

      {particles, occupied, cooldowns, residue} =
        Enum.reduce(
          state.particles,
          {[], state.occupied_columns, state.column_cooldowns, state.residue || %{}},
          fn
            particle, {acc, occupied, cooldowns, residue} ->
              {updated, occupied, cooldowns, residue} =
                case state.direction do
                  :classic -> step_classic(particle, state, dt, seconds, occupied, cooldowns, residue, now)
                  :ring -> {advance_particle(particle, state, dt), occupied, cooldowns, residue}
                end

              if alive?(updated, state) do
                {[updated | acc], occupied, cooldowns, residue}
              else
                {acc, occupied, cooldowns, residue}
              end
          end
        )

      %State{
        state
        | particles: Enum.reverse(particles),
          particle_count: length(particles),
          occupied_columns: occupied,
          column_cooldowns: prune_cooldowns(cooldowns, now),
          residue: prune_residue(residue, seconds, cells_per_sec(state)),
          now: now,
          seconds: seconds
      }
    end

    # Head fall speed in cells per second (drops all share the classic pace).
    defp cells_per_sec(%State{speed: speed, global_speed: global_speed}) do
      @classic_speed * speed * (global_speed || 1.0)
    end

    def shimmer(%State{particles: particles} = state) do
      particles =
        Enum.map(particles, fn %Particle{tail: tail} = particle ->
          tail =
            Enum.map(tail, fn flicker ->
              if :rand.uniform() < Matrix.shimmer_chance(), do: random_flicker(), else: flicker
            end)

          %Particle{particle | tail: tail}
        end)

      residue =
        Map.new(state.residue || %{}, fn {key, {_flicker, born, trail_length}} = entry ->
          if :rand.uniform() < Matrix.shimmer_chance() do
            {key, {residue_brightness(), born, trail_length}}
          else
            entry
          end
        end)

      %State{state | particles: particles, residue: residue}
    end

    def render(%State{} = state) do
      canvas = Canvas.new(state.width, state.height)
      ctx = render_ctx(state)
      canvas = draw_residue(canvas, state)

      canvas =
        state.particles
        |> Enum.sort_by(fn %Particle{z: z} -> z end)
        |> Enum.reduce(canvas, &draw_particle(&2, &1, state, ctx))

      %State{state | canvas: canvas}
    end

    defp render_ctx(%{direction: :ring, sway_scale: scale}) when scale == 0.0, do: %{sway: false}

    defp render_ctx(%{direction: :ring} = state) do
      {amplitude, phase} =
        Sway.params(state.sway_scale, state.sway_speed, state.sway_mode, state.seconds || 0.0)

      %{sway: true, amplitude: amplitude, phase: phase}
    end

    defp render_ctx(_), do: %{sway: false}

    @doc false
    def tail_segment_brightness(segment_index) do
      @tail_brightness_base * :math.pow(@tail_decay, segment_index)
    end

    @doc false
    def soft_weights(pos_float) do
      low = trunc(pos_float)
      frac = pos_float - low
      {1.0 - frac, frac, low}
    end

    @doc false
    def bilinear_weights(fx, fy) do
      {(1.0 - fx) * (1.0 - fy), fx * (1.0 - fy), (1.0 - fx) * fy, fx * fy}
    end

    @doc false
    def segment_y_drawn(lane, seg_x, width, amplitude, phase, sway_scale) do
      lane_eff = lane_effective(lane, sway_scale)
      lane_eff + Sway.offset(seg_x, width, amplitude, phase)
    end

    # Classic rain: the head is a single, instantly full-bright pixel that
    # snaps from cell to cell. No soft fade-in, no z-dimming, no moving tail —
    # the trail it leaves behind is the deposited residue.
    defp draw_particle(canvas, %Particle{} = particle, %State{direction: :classic} = state, _ctx) do
      y = trunc(particle.y)

      if y >= 0 and y < state.height do
        frac = particle.y - y
        ease = smoothstep(min(1.0, frac / @head_ease_frac))
        Matrix.add_pixel(canvas, {trunc(particle.x), y}, Matrix.scale_color(@head_color, ease))
      else
        canvas
      end
    end

    defp draw_particle(canvas, %Particle{} = particle, state, %{sway: true} = ctx) do
      fade = fade_multiplier(particle, state)

      canvas =
        particle.tail
        |> Enum.with_index()
        |> Enum.reduce(canvas, fn {flicker, index}, acc ->
          brightness = tail_segment_brightness(index)
          color = Matrix.scale_color(@tail_base, particle.z * flicker * brightness * fade)
          {seg_x, lane} = ring_segment(particle, index)
          y_drawn = segment_y_drawn(lane, seg_x, state.width, ctx.amplitude, ctx.phase, state.sway_scale)
          put_pixel_bilinear(acc, seg_x, y_drawn, color, state.width, state.height)
        end)

      head_color = Matrix.scale_color(@head_color, particle.z * fade)
      y_drawn = segment_y_drawn(particle.y, particle.x, state.width, ctx.amplitude, ctx.phase, state.sway_scale)
      put_pixel_bilinear(canvas, particle.x, y_drawn, head_color, state.width, state.height)
    end

    defp draw_particle(canvas, %Particle{} = particle, state, %{sway: false}) do
      fade = fade_multiplier(particle, state)

      canvas =
        particle.tail
        |> Enum.with_index()
        |> Enum.reduce(canvas, fn {flicker, index}, acc ->
          brightness = tail_segment_brightness(index)
          color = Matrix.scale_color(@tail_base, particle.z * flicker * brightness * fade)
          tail_pos = tail_position(particle, index, state.direction)
          put_pixel_soft(acc, state, tail_pos, color)
        end)

      head_color = Matrix.scale_color(@head_color, particle.z * fade)
      put_pixel_soft(canvas, state, {particle.x, particle.y}, head_color)
    end

    defp ring_segment(%Particle{x: x, y: y, sign: sign}, index) do
      offset = (index + 1) * -sign
      {x + offset, y}
    end

    # Compress outer lanes when sway amplitude is large so crests stay visible.
    defp lane_effective(lane, sway_scale) when sway_scale > 1.5 do
      3.5 + (lane - 3.5) * max(0.4, 1 - (sway_scale - 1.5) / 4)
    end

    defp lane_effective(lane, _sway_scale), do: lane

    defp put_pixel_bilinear(canvas, x_float, y_float, color, width, height) do
      {_wx0, wx1, x_low} = soft_weights(x_float)
      {_wy0, wy1, y_low} = soft_weights(y_float)
      {w00, w10, w01, w11} = bilinear_weights(wx1, wy1)

      x0 = Integer.mod(x_low, width)
      x1 = Integer.mod(x_low + 1, width)

      [
        {x0, y_low, w00},
        {x1, y_low, w10},
        {x0, y_low + 1, w01},
        {x1, y_low + 1, w11}
      ]
      |> Enum.reduce(canvas, fn {x, y, weight}, acc ->
        if y >= 0 and y < height do
          Matrix.add_pixel(acc, {x, y}, Matrix.scale_color(color, weight))
        else
          acc
        end
      end)
    end

    defp tail_position(%Particle{x: x, y: y}, index, :classic) do
      {x, y - index - 1}
    end

    defp tail_position(%Particle{x: x, y: y, sign: sign}, index, :ring) do
      offset = (index + 1) * -sign
      {x + offset, y}
    end

    defp put_pixel_soft(canvas, state, {x_float, y_float}, color) do
      case state.direction do
        :classic ->
          put_pixel_soft_axis(canvas, :y, {x_float, y_float}, color, state.width)

        :ring ->
          put_pixel_soft_axis(canvas, :x, {x_float, y_float}, color, state.width)
      end
    end

    defp put_pixel_soft_axis(canvas, :y, {x_float, y_float}, color, _width) do
      {w0, w1, low} = soft_weights(y_float)
      x = trunc(x_float)

      canvas
      |> Matrix.add_pixel({x, low}, Matrix.scale_color(color, w0))
      |> Matrix.add_pixel({x, low + 1}, Matrix.scale_color(color, w1))
    end

    defp put_pixel_soft_axis(canvas, :x, {x_float, y_float}, color, width) do
      {w0, w1, low} = soft_weights(x_float)
      y = trunc(y_float)
      x0 = Integer.mod(low, width)
      x1 = Integer.mod(low + 1, width)

      canvas
      |> Matrix.add_pixel({x0, y}, Matrix.scale_color(color, w0))
      |> Matrix.add_pixel({x1, y}, Matrix.scale_color(color, w1))
    end

    # Classic snake rain: the drop slides down one column, then hops to the top
    # of the next visible column to the right, leaving a static residue trail in
    # every cell it crosses. After @snake_columns_* hops it runs out and dies.
    defp step_classic(%Particle{} = particle, state, dt, seconds, occupied, cooldowns, residue, now) do
      fade_age =
        if fading?(particle, state), do: particle.fade_age + dt, else: particle.fade_age

      new_y = particle.y + particle.speed * dt

      cond do
        new_y < state.height ->
          updated = %Particle{particle | y: new_y, age: particle.age + dt, fade_age: fade_age}
          {updated, occupied, cooldowns, deposit_residue(residue, seconds, particle, updated, state)}

        (particle.columns_left || 0) > 0 and
            next_free_column(particle.column, occupied, state) != nil ->
          residue =
            deposit_residue(residue, seconds, particle, %Particle{particle | y: state.height * 1.0}, state)

          next_col = next_free_column(particle.column, occupied, state)

          updated = %Particle{
            particle
            | x: next_col * 1.0,
              y: new_y - state.height,
              column: next_col,
              columns_left: particle.columns_left - 1,
              age: particle.age + dt,
              fade_age: 0.0
          }

          occupied = occupied |> MapSet.delete(particle.column) |> MapSet.put(next_col)
          {updated, occupied, Map.put(cooldowns, particle.column, column_cooldown(now)), residue}

        particle.y < state.height ->
          # Last column done: fill it to the bottom, then keep falling so it dies.
          residue =
            deposit_residue(residue, seconds, particle, %Particle{particle | y: state.height * 1.0}, state)

          updated = %Particle{particle | y: new_y, age: particle.age + dt, fade_age: fade_age}
          occupied = MapSet.delete(occupied, particle.column)
          {updated, occupied, Map.put(cooldowns, particle.column, column_cooldown(now)), residue}

        true ->
          updated = %Particle{particle | y: new_y, age: particle.age + dt, fade_age: fade_age}
          {updated, occupied, cooldowns, residue}
      end
    end

    defp column_cooldown(now), do: now + @column_cooldown_min + :rand.uniform() * @column_cooldown_span

    defp classic_head_speed do
      @classic_speed * (1.0 + (:rand.uniform() * 2.0 - 1.0) * @classic_speed_jitter)
    end

    # Next free (unoccupied) visible column to the right, wrapping at the edge.
    # Returns nil when every other column already has a head, so the drop dies
    # instead of colliding with another white head.
    defp next_free_column(col, occupied, state) do
      cols = visible_columns(state)
      n = length(cols)

      start =
        case Enum.find_index(cols, &(&1 == col)) do
          nil -> 0
          idx -> idx + 1
        end

      Enum.reduce_while(0..(n - 1), nil, fn off, _acc ->
        cand = Enum.at(cols, rem(start + off, n))
        if MapSet.member?(occupied, cand), do: {:cont, nil}, else: {:halt, cand}
      end)
    end

    # Ring mode: orbit horizontally around the wall (classic uses step_classic).
    defp advance_particle(%Particle{} = particle, state, dt) do
      effective = particle.speed * particle.z * dt

      %Particle{
        particle
        | x: Matrix.wrap_x(particle.x + particle.sign * effective, state.width),
          age: particle.age + dt,
          fade_age: particle.fade_age
      }
    end

    defp alive?(%Particle{} = _particle, %{direction: :ring}), do: true

    defp alive?(%Particle{fade_age: fade_age} = particle, state) do
      if fading?(particle, state) do
        fade_age < @fade_duration
      else
        true
      end
    end

    defp fading?(%Particle{} = particle, %{direction: :classic, tail_length: tail_length, height: height}) do
      particle.y - tail_length > height
    end

    defp fading?(_, _), do: false

    defp fade_multiplier(%Particle{} = particle, state) do
      if fading?(particle, state) and particle.fade_age > 0 do
        max(0.0, 1.0 - particle.fade_age / @fade_duration)
      else
        1.0
      end
    end

    # The head writes a static trail into the cells it crosses: green glyphs at
    # random brightness, sometimes a black gap. Each cell stores when it was laid
    # down plus the drop's trail length (in cells), so it stays lit only while the
    # head is within `trail_length` cells past it (see prune_residue/3).
    defp deposit_residue(residue, seconds, %Particle{} = old, %Particle{} = updated, state) do
      col = trunc(updated.x)
      from = max(trunc(old.y) + 1, 0)
      to = min(trunc(updated.y), state.height - 1)
      trail_length = old.trail_length || @trail_length_max

      Enum.reduce(from..to//1, residue, fn row, acc ->
        if :rand.uniform() < @trail_gap_chance do
          Map.delete(acc, {col, row})
        else
          Map.put(acc, {col, row}, {residue_brightness(), seconds, trail_length})
        end
      end)
    end

    # Length-based, but measured in wall time so it's independent of how many drops
    # are depositing: a cell lives until the head has moved trail_length cells past
    # it, i.e. (age × cells_per_sec) ≥ trail_length.
    defp prune_residue(residue, _seconds, cells_per_sec) when cells_per_sec <= 0, do: residue

    defp prune_residue(residue, seconds, cells_per_sec) do
      Map.filter(residue, fn {_key, {_flicker, born, trail_length}} ->
        (seconds - born) * cells_per_sec < trail_length * @trail_hold
      end)
    end

    defp residue_brightness do
      :rand.uniform() * (@residue_bright_max - @residue_bright_min) + @residue_bright_min
    end

    defp smoothstep(t), do: t * t * (3.0 - 2.0 * t)

    defp draw_residue(canvas, %State{direction: :classic, residue: residue})
         when is_map(residue) do
      Enum.reduce(residue, canvas, fn {{x, y}, {flicker, _born, _trail_length}}, acc ->
        value = flicker * @trail_brightness
        Matrix.add_pixel(acc, {x, y}, Matrix.scale_color(@tail_base, value))
      end)
    end

    defp draw_residue(canvas, _state), do: canvas

    defp pick_classic_column(state) do
      now = state.now || monotonic_now()

      cooling =
        state.column_cooldowns
        |> Enum.filter(fn {_col, until} -> until > now end)
        |> Enum.map(fn {col, _} -> col end)
        |> MapSet.new()

      occupied = state.occupied_columns || MapSet.new()

      state
      |> visible_columns()
      |> Enum.reject(fn col -> MapSet.member?(occupied, col) or MapSet.member?(cooling, col) end)
      |> case do
        [] -> nil
        free -> Enum.random(free)
      end
    end

    defp pick_ring_spawn(state) do
      min_dist = state.tail_length * 3
      sign = if :rand.uniform() < state.counterflow, do: -1, else: 1

      Enum.reduce_while(1..32, nil, fn _attempt, _acc ->
        lane = :rand.uniform(state.height) - 1
        x = :rand.uniform() * state.width

        if lane_clear?(state, lane, x, sign, min_dist) do
          {:halt, {x, lane, sign}}
        else
          {:cont, nil}
        end
      end)
    end

    defp lane_clear?(state, lane, spawn_x, spawn_sign, min_dist) do
      Enum.all?(state.particles, fn %Particle{y: y, x: head_x, sign: head_sign} ->
        trunc(y) != lane or
          head_sign != spawn_sign or
          ring_distance_behind(spawn_x, head_x, state.width, spawn_sign) >= min_dist
      end)
    end

    defp ring_distance_behind(spawn_x, head_x, width, 1) do
      Matrix.wrap_x(spawn_x - head_x, width)
    end

    defp ring_distance_behind(spawn_x, head_x, width, -1) do
      Matrix.wrap_x(head_x - spawn_x, width)
    end

    defp new_classic_particle(state, column) do
      %Particle{
        x: column * 1.0,
        y: classic_spawn_y(state),
        z: :rand.uniform() * 0.5 + 0.5,
        speed: classic_head_speed(),
        sign: 1,
        age: 0.0,
        fade_age: 0.0,
        tail: new_tail(state.tail_length),
        column: column,
        columns_left: @snake_columns_min + :rand.uniform(@snake_columns_max - @snake_columns_min + 1) - 1,
        trail_length: @trail_length_min + :rand.uniform(@trail_length_max - @trail_length_min + 1) - 1
      }
    end

    defp new_ring_particle(state, x, lane, sign) do
      %Particle{
        x: x,
        y: lane * 1.0,
        z: :rand.uniform() * 0.5 + 0.5,
        speed: random_particle_speed(),
        sign: sign,
        age: 0.0,
        fade_age: 0.0,
        tail: new_tail(state.tail_length),
        column: lane
      }
    end

    # Stagger entry times by spawning drops at random heights above the screen.
    defp classic_spawn_y(%State{speed: speed, global_speed: global_speed}) do
      rate = @classic_speed * speed * (global_speed || 1.0)
      stagger = @spawn_stagger_min + :rand.uniform() * (@spawn_stagger_max - @spawn_stagger_min)
      -:rand.uniform() * rate * stagger
    end

    defp new_tail(length) do
      Enum.map(1..length, fn _ -> random_flicker() end)
    end

    defp random_flicker, do: :rand.uniform() * 0.25 + 0.75

    # Ring mode only: per-drop variance for the orbiting streaks.
    # Classic rain uses the fixed @classic_speed instead.
    defp random_particle_speed do
      case :rand.uniform() do
        r when r < 0.2 -> 2.5 + :rand.uniform() * 2.5
        r when r < 0.85 -> 5.0 + :rand.uniform() * 9.0
        _ -> 14.0 + :rand.uniform() * 14.0
      end
    end

    defp insert_particle(%State{} = state, particle) do
      occupied =
        if state.direction == :classic do
          MapSet.put(state.occupied_columns || MapSet.new(), particle.column)
        else
          state.occupied_columns || MapSet.new()
        end

      particles = [particle | state.particles]

      %State{
        state
        | particles: particles,
          particle_count: state.particle_count + 1,
          occupied_columns: occupied
      }
    end

    defp visible_columns(%{width: width, pitch: pitch, panel_width: panel_width}) do
      Enum.filter(0..(width - 1), fn x -> rem(x, pitch) < panel_width end)
    end

    defp prune_cooldowns(cooldowns, now) do
      Map.filter(cooldowns, fn {_col, until} -> until > now end)
    end

    defp monotonic_now, do: System.monotonic_time(:millisecond) / 1000.0
  end

  alias Octopus.Canvas

  def shimmer_chance, do: @shimmer_chance

  def name(), do: "Matrix"

  def config_schema do
    %{
      bleeding: {"Bleeding", :float, %{default: 10.0, min: 0.0, max: 100.0, step: 1.0}}
    }
  end

  def list_modes do
    apply(@mode_presets, :list_modes, [__MODULE__])
  end

  def mode_config(mode_id) do
    config =
      apply(@mode_presets, :config_for, [__MODULE__, mode_id]) ||
        legacy_mode_config(apply(@mode_presets, :mode_slug, [mode_id]))

    case config do
      %{} = empty when map_size(empty) == 0 -> %{}
      value -> normalize_mode_config(value)
    end
  end

  def normalize_mode_config(config) do
    config
    |> coerce_config_atoms()
    |> Map.update(:direction, :classic, &coerce_direction/1)
    |> Map.update(:tail_length, 4, &trunc/1)
    |> Map.update(:counterflow, 0.0, &coerce_float/1)
    |> Map.update(:speed, 6.0, &coerce_float/1)
    |> Map.update(:afterglow, 60, &trunc/1)
    |> Map.update(:density, 1, &trunc/1)
    |> Map.update(:max_particles, 36, &trunc/1)
    |> Map.update(:sway_scale, 0.0, &coerce_float/1)
    |> Map.update(:sway_speed, 0.5, &coerce_float/1)
    |> Map.update(:sway_mode, :wobble, &coerce_sway_mode/1)
  end

  def builtin_presets do
    [
      %{
        slug: "matrix",
        name: "matrix",
        accent_color: "#2ECC71",
        config: legacy_mode_config("matrix")
      },
      %{
        slug: "matrix-ring",
        name: "matrix ring",
        accent_color: "#2ECC71",
        config: legacy_mode_config("matrix-ring")
      }
    ]
  end

  def legacy_mode_config("matrix") do
    %{
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
  end

  def legacy_mode_config("matrix-ring") do
    %{
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
  end

  def legacy_mode_config(_), do: %{}

  def mode_tweakables(mode_id) do
    mode_tweakables_for(apply(@mode_presets, :mode_slug, [mode_id]))
  end

  def mode_tweakables_for("matrix-ring"), do: mode_tweakables_for("matrix")

  def mode_tweakables_for("matrix") do
    [
      %{
        key: :direction,
        label: "Direction",
        type: :choice,
        default: :classic,
        options: [{:classic, "Vertical"}, {:ring, "Ring"}]
      },
      %{
        key: :speed,
        label: "Speed",
        type: :slider,
        min: 0.1,
        max: 10.0,
        step: 0.05,
        default: 6.0
      },
      %{
        key: :afterglow,
        label: "Afterglow",
        type: :slider,
        min: 0,
        max: 300,
        step: 10,
        unit: "ms",
        default: 60,
        runtime: true
      },
      %{
        key: :bleeding,
        label: "Bleeding",
        type: :slider,
        min: 0.0,
        max: 100.0,
        step: 1.0,
        unit: "%",
        default: 10.0,
        runtime: true
      },
      %{
        key: :density,
        label: "Density",
        type: :slider,
        min: 1,
        max: 10,
        step: 1,
        default: 1
      },
      %{
        key: :max_particles,
        label: "Max particles",
        type: :slider,
        min: 1,
        max: 400,
        step: 1,
        default: 36
      },
      %{
        key: :tail_length,
        label: "Tail length",
        type: :slider,
        min: 2,
        max: 10,
        step: 1,
        default: 4
      },
      %{
        key: :counterflow,
        label: "Counterflow",
        type: :slider,
        min: 0.0,
        max: 1.0,
        step: 0.05,
        default: 0.0,
        visible_when: {:direction, [:ring]}
      },
      %{
        key: :sway_scale,
        label: "Sway strength",
        type: :slider,
        min: 0.0,
        max: 3.0,
        step: 0.1,
        default: 0.0,
        visible_when: {:direction, [:ring]}
      },
      %{
        key: :sway_speed,
        label: "Sway speed",
        type: :slider,
        min: 0.0,
        max: 3.0,
        step: 0.05,
        default: 0.5,
        visible_when: {:direction, [:ring]}
      },
      %{
        key: :sway_mode,
        label: "Sway mode",
        type: :select,
        options: [{"Wobble", :wobble}, {"Pendulum", :pendulum}],
        default: :wobble,
        visible_when: {:direction, [:ring]}
      }
    ]
  end

  def mode_tweakables_for(_), do: []

  def compatible?() do
    installation = Octopus.App.get_installation_info()

    installation.panel_count >= 8 and installation.panel_width == 8 and
      installation.panel_height == 8
  end

  def get_config(%State{} = state) do
    %{
      direction: state.direction,
      speed: state.speed,
      density: state.density,
      max_particles: state.max_particles,
      tail_length: state.tail_length,
      counterflow: state.counterflow,
      sway_scale: state.sway_scale,
      sway_speed: state.sway_speed,
      sway_mode: state.sway_mode,
      afterglow: state.afterglow
    }
  end

  def handle_config(config, %State{} = state) do
    config = config |> coerce_config_atoms() |> normalize_mode_config()
    direction_changed = Map.has_key?(config, :direction) && coerce_direction(config.direction) != state.direction

    state =
      state
      |> apply_config(config)
      |> then(fn s -> if direction_changed, do: reset_particles(s), else: s end)
      |> enforce_particle_cap()

    {:noreply, state}
  end

  def now_playing_meta(config) do
    config = normalize_mode_config(config)
    direction = Map.get(config, :direction, :classic)
    max = Map.get(config, :max_particles, 36)
    density = Map.get(config, :density, 1)
    tail = Map.get(config, :tail_length, 4)
    sway_scale = Map.get(config, :sway_scale, 0.0)

    direction_label =
      case direction do
        :ring -> "ring"
        _ -> "vertical"
      end

    meta = [
      direction_label,
      "tail #{tail}",
      "#{max} particles max",
      "density #{density}"
    ]

    if direction == :ring and sway_scale > 0 do
      meta ++ ["sway #{format_num(sway_scale)}"]
    else
      meta
    end
  end

  defp format_num(n) when is_float(n), do: :erlang.float_to_binary(n, decimals: 1)
  defp format_num(n), do: to_string(n)

  def app_init(config) do
    Octopus.App.configure_display(layout: :gapped_panels)
    Octopus.Params.Global.subscribe()

    global_speed = Octopus.Params.Global.speed()
    display_info = Octopus.App.get_display_info()
    installation = Octopus.App.get_installation_info()

    width = trunc(display_info.width)
    height = trunc(display_info.height)
    pitch = installation.panel_width + installation.panel_gap

    canvas = Canvas.new(width, height)
    :timer.send_interval(trunc(1000 / 60), :tick)
    :timer.send_interval(50, :spawn_particles)
    :timer.send_interval(50, :shimmer)

    state =
      %State{
        canvas: canvas,
        particles: [],
        particle_count: 0,
        width: width,
        height: height,
        pitch: pitch,
        panel_width: installation.panel_width,
        global_speed: global_speed,
        speed: 6.0,
        density: 1,
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
        residue: %{},
        now: 0.0
      }
      |> apply_config(normalize_mode_config(config))
      |> enforce_particle_cap()

    {:ok, state}
  end

  def handle_info({:param_updated, :speed, new_value}, %State{} = state) do
    {:noreply, %{state | global_speed: new_value}}
  end

  def handle_info({:param_updated, _key, _value}, %State{} = state) do
    {:noreply, state}
  end

  def handle_info(:shimmer, %State{} = state) do
    {:noreply, State.shimmer(state)}
  end

  def handle_info(:spawn_particles, %State{} = state) do
    state = enforce_particle_cap(state)

    state =
      if state.particle_count < state.max_particles do
        case desired_spawn_amount(state) do
          0 -> state
          amount -> State.spawn_particles(state, amount)
        end
      else
        state
      end

    {:noreply, state}
  end

  def handle_info(:tick, %State{} = state) do
    state = enforce_particle_cap(state)
    dt = 1 / 60 * state.speed * state.global_speed
    state = state |> State.update(dt) |> State.render()
    Octopus.App.update_display(state.canvas, :rgb, easing_interval: trunc(state.afterglow || 0))
    {:noreply, state}
  end

  defp desired_spawn_amount(%State{} = state) do
    if :rand.uniform() < spawn_tick_chance(state) do
      max(1, trunc(state.density))
    else
      0
    end
  end

  defp spawn_tick_chance(%State{density: density}) do
    # Default density 1 spawns on roughly every other tick.
    min(1.0, density / 2.0)
  end

  @doc false
  def wrap_x(x, width) when width > 0 do
    fmod = :math.fmod(x, width * 1.0)
    if fmod < 0, do: fmod + width, else: fmod
  end

  @doc false
  def scale_color({_r, _g, _b}, factor) when factor <= 0, do: {0, 0, 0}

  def scale_color({r, g, b}, factor) do
    {trunc(r * factor), trunc(g * factor), trunc(b * factor)}
  end

  @doc false
  def add_pixel(canvas, {_x, _y}, {0, 0, 0}), do: canvas

  def add_pixel(canvas, {x, y}, {r, g, b}) do
    {er, eg, eb} = Canvas.get_pixel(canvas, {x, y})
    Canvas.put_pixel(canvas, {x, y}, {min(255, er + r), min(255, eg + g), min(255, eb + b)})
  end

  @config_keys [
    :direction,
    :speed,
    :density,
    :max_particles,
    :tail_length,
    :counterflow,
    :sway_scale,
    :sway_speed,
    :sway_mode,
    :afterglow
  ]

  defp apply_config(%State{} = state, config) do
    config
    |> Enum.reduce(state, fn
      {key, value}, acc when key in @config_keys -> Map.put(acc, key, coerce_config_value(key, value))
      _, acc -> acc
    end)
  end

  defp coerce_config_value(:direction, value), do: coerce_direction(value)
  defp coerce_config_value(:tail_length, value), do: trunc(value)
  defp coerce_config_value(:density, value), do: trunc(value)
  defp coerce_config_value(:max_particles, value), do: trunc(value)
  defp coerce_config_value(:speed, value), do: coerce_float(value)
  defp coerce_config_value(:counterflow, value), do: coerce_float(value)
  defp coerce_config_value(:sway_scale, value), do: coerce_float(value)
  defp coerce_config_value(:sway_speed, value), do: coerce_float(value)
  defp coerce_config_value(:sway_mode, value), do: coerce_sway_mode(value)
  defp coerce_config_value(:afterglow, value), do: trunc(value)

  defp coerce_sway_mode(mode), do: Octopus.Sway.normalize_mode(mode)

  defp reset_particles(%State{} = state) do
    %{
      state
      | particles: [],
        particle_count: 0,
        occupied_columns: MapSet.new(),
        column_cooldowns: %{},
        residue: %{}
    }
  end

  # Drop extras when max_particles was lowered (e.g. preset override → debug cap).
  defp enforce_particle_cap(%State{particle_count: count, max_particles: max} = state)
       when count > max,
       do: reset_particles(state)

  defp enforce_particle_cap(state), do: state

  defp coerce_config_atoms(config) when is_map(config) do
    Map.new(config, fn
      {k, v} when is_binary(k) -> {String.to_existing_atom(k), v}
      {k, v} -> {k, v}
    end)
  rescue
    ArgumentError ->
      Map.new(config, fn {k, v} -> {coerce_key(k), v} end)
  end

  defp coerce_key(k) when is_atom(k), do: k
  defp coerce_key("true"), do: true
  defp coerce_key("false"), do: false
  defp coerce_key(k) when is_binary(k), do: String.to_atom(k)

  defp coerce_direction(:classic), do: :classic
  defp coerce_direction(:ring), do: :ring
  defp coerce_direction("classic"), do: :classic
  defp coerce_direction("ring"), do: :ring
  defp coerce_direction(_), do: :classic

  defp coerce_float(v) when is_integer(v), do: v * 1.0
  defp coerce_float(v) when is_float(v), do: v
  defp coerce_float(v) when is_binary(v), do: String.to_float(v)
  defp coerce_float(v), do: v
end
