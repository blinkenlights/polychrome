defmodule Octopus.Apps.Matrix do
  use Octopus.App, category: :animation

  @mode_presets Module.concat(["Octopus", "AppModePresets"])

  @shimmer_chance 0.03
  @default_trail_length 135
  @default_speed 8.0
  @heads_per_panel_target 3
  @column_min_gap 3
  @fade_below 4

  defmodule Particle do
    defstruct [:x, :y, :z, :speed, :age, :fade_age, :column, :columns_left, :trail_length]
  end

  defmodule State do
    alias Octopus.Apps.Matrix, as: Matrix
    alias Octopus.Canvas

    @head_color {160, 255, 160}
    @tail_base {40, 255, 70}
    @trail_brightness 0.55
    @trail_gap_chance 0.35
    @trail_hold 3.0
    @residue_bright_min 0.4
    @residue_bright_max 1.0
    @head_ease_frac 0.25
    @fade_duration 0.5
    @classic_speed 1.0
    @spawn_stagger_min 2.0
    @spawn_stagger_max 10.0
    @column_cooldown_min 0.8
    @column_cooldown_span 4.0
    @snake_columns_min 1
    @snake_columns_max 5
    @classic_speed_jitter 0.08

    defstruct [
      :canvas,
      :particles,
      :particle_count,
      :width,
      :height,
      :pitch,
      :panel_width,
      :panel_count,
      :global_speed,
      :speed,
      :density,
      :max_particles,
      :trail_length,
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

    defp spawn_one(%State{} = state) do
      case pick_classic_column(state) do
        nil -> state
        column -> insert_particle(state, new_classic_particle(state, column))
      end
    end

    def update(%State{} = state, dt) do
      now = monotonic_now()
      seconds = (state.seconds || 0.0) + dt

      {particles, occupied, cooldowns, residue} =
        Enum.reduce(
          state.particles,
          {[], state.occupied_columns, state.column_cooldowns, state.residue || %{}},
          fn particle, {acc, occupied, cooldowns, residue} ->
            {updated, occupied, cooldowns, residue} =
              step_classic(particle, state, dt, seconds, occupied, cooldowns, residue, now)

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

    defp cells_per_sec(%State{speed: speed, global_speed: global_speed}) do
      @classic_speed * speed * (global_speed || 1.0)
    end

    def shimmer(%State{} = state) do
      residue =
        Map.new(state.residue || %{}, fn {key, {_flicker, born, trail_length}} = entry ->
          if :rand.uniform() < Matrix.shimmer_chance() do
            {key, {residue_brightness(), born, trail_length}}
          else
            entry
          end
        end)

      %State{state | residue: residue}
    end

    def render(%State{} = state) do
      canvas =
        state
        |> draw_residue()
        |> then(fn canvas ->
          state.particles
          |> Enum.sort_by(fn %Particle{z: z} -> z end)
          |> Enum.reduce(canvas, &draw_particle(&2, &1, state))
        end)

      %State{state | canvas: canvas}
    end

    @doc false
    def soft_weights(pos_float) do
      low = trunc(pos_float)
      frac = pos_float - low
      {1.0 - frac, frac, low}
    end

    defp draw_particle(canvas, %Particle{} = particle, %State{} = state) do
      y = trunc(particle.y)

      if y >= 0 and y < state.height do
        frac = particle.y - y
        ease = smoothstep(min(1.0, frac / @head_ease_frac))
        Matrix.add_pixel(canvas, {trunc(particle.x), y}, Matrix.scale_color(@head_color, ease))
      else
        canvas
      end
    end

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

        if MapSet.member?(occupied, cand) or not column_clear?(cand, occupied) do
          {:cont, nil}
        else
          {:halt, cand}
        end
      end)
    end

    defp column_clear?(col, occupied, min_gap \\ Matrix.column_min_gap()) do
      Enum.all?(occupied, fn other -> abs(col - other) >= min_gap end)
    end

    defp alive?(%Particle{fade_age: fade_age} = particle, state) do
      if fading?(particle, state) do
        fade_age < @fade_duration
      else
        true
      end
    end

    defp fading?(%Particle{y: y}, %{height: height}), do: y > height + Matrix.fade_below()

    defp deposit_residue(residue, seconds, %Particle{} = old, %Particle{} = updated, state) do
      col = trunc(updated.x)
      from = max(trunc(old.y) + 1, 0)
      to = min(trunc(updated.y), state.height - 1)
      trail_length = old.trail_length || state.trail_length || Matrix.default_trail_length()

      Enum.reduce(from..to//1, residue, fn row, acc ->
        if :rand.uniform() < @trail_gap_chance do
          Map.delete(acc, {col, row})
        else
          Map.put(acc, {col, row}, {residue_brightness(), seconds, trail_length})
        end
      end)
    end

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

    defp draw_residue(%State{residue: residue} = state) when is_map(residue) do
      canvas = Canvas.new(state.width, state.height)

      Enum.reduce(residue, canvas, fn {{x, y}, {flicker, _born, _trail_length}}, acc ->
        value = flicker * @trail_brightness
        Matrix.add_pixel(acc, {x, y}, Matrix.scale_color(@tail_base, value))
      end)
    end

    defp draw_residue(%State{} = state), do: Canvas.new(state.width, state.height)

    defp pick_classic_column(state) do
      now = state.now || monotonic_now()

      cooling =
        state.column_cooldowns
        |> Enum.filter(fn {_col, until} -> until > now end)
        |> Enum.map(fn {col, _} -> col end)
        |> MapSet.new()

      occupied = state.occupied_columns || MapSet.new()

      free =
        state
        |> visible_columns()
        |> Enum.reject(fn col ->
          MapSet.member?(occupied, col) or
            MapSet.member?(cooling, col) or
            not column_clear?(col, occupied)
        end)

      case free do
        [] -> nil
        columns -> pick_balanced_column(columns, occupied, state)
      end
    end

    defp pick_balanced_column(free, occupied, state) do
      pitch = state.pitch

      by_panel = Enum.group_by(free, &div(&1, pitch))

      panel_counts =
        occupied
        |> MapSet.to_list()
        |> Enum.group_by(&div(&1, pitch))
        |> Map.new(fn {panel, cols} -> {panel, length(cols)} end)

      target = Matrix.heads_per_panel_target()

      panel_id =
        by_panel
        |> Map.keys()
        |> Enum.filter(fn panel -> Map.get(panel_counts, panel, 0) < target end)
        |> case do
          [] ->
            by_panel
            |> Map.keys()
            |> Enum.min_by(&Map.get(panel_counts, &1, 0))

          candidates ->
            Enum.min_by(candidates, &Map.get(panel_counts, &1, 0))
        end

      by_panel
      |> Map.fetch!(panel_id)
      |> pick_spread_column(occupied)
    end

    defp pick_spread_column(cols, occupied) do
      Enum.max_by(cols, &min_column_distance(&1, occupied))
    end

    defp min_column_distance(col, occupied) do
      case MapSet.to_list(occupied) do
        [] -> 999
        others -> others |> Enum.map(fn other -> abs(col - other) end) |> Enum.min()
      end
    end

    defp new_classic_particle(state, column) do
      %Particle{
        x: column * 1.0,
        y: classic_spawn_y(state),
        z: :rand.uniform() * 0.5 + 0.5,
        speed: classic_head_speed(),
        age: 0.0,
        fade_age: 0.0,
        column: column,
        columns_left: @snake_columns_min + :rand.uniform(@snake_columns_max - @snake_columns_min + 1) - 1,
        trail_length: state.trail_length || Matrix.default_trail_length()
      }
    end

    defp classic_spawn_y(%State{speed: speed, global_speed: global_speed}) do
      rate = @classic_speed * speed * (global_speed || 1.0)
      stagger = @spawn_stagger_min + :rand.uniform() * (@spawn_stagger_max - @spawn_stagger_min)
      -:rand.uniform() * rate * stagger
    end

    defp insert_particle(%State{} = state, particle) do
      occupied = MapSet.put(state.occupied_columns || MapSet.new(), particle.column)
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
  def default_trail_length, do: @default_trail_length
  def column_min_gap, do: @column_min_gap
  def heads_per_panel_target, do: @heads_per_panel_target
  def fade_below, do: @fade_below

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
    case apply(@mode_presets, :config_for, [__MODULE__, mode_id]) do
      nil -> %{}
      config -> normalize_mode_config(config)
    end
  end

  def normalize_mode_config(config) do
    config = coerce_config_atoms(config)

    trail_length =
      cond do
        Map.has_key?(config, :trail_length) ->
          trunc(config.trail_length)

        Map.has_key?(config, :tail_length) ->
          val = trunc(config.tail_length)
          if val < 10, do: @default_trail_length, else: val

        true ->
          @default_trail_length
      end

    config
    |> Map.drop([:direction, :tail_length, :counterflow, :sway_scale, :sway_speed, :sway_mode])
    |> Map.put(:trail_length, trail_length)
    |> Map.update(:speed, @default_speed, &coerce_float/1)
    |> Map.update(:afterglow, 60, &trunc/1)
    |> Map.update(:density, 1, &trunc/1)
    |> Map.update(:max_particles, 24, &trunc/1)
  end

  def mode_tweakables(mode_id) do
    mode_tweakables_for(apply(@mode_presets, :mode_slug, [mode_id]))
  end

  def mode_tweakables_for("matrix") do
    [
      %{
        key: :speed,
        label: "Speed",
        type: :slider,
        min: 0.1,
        max: 10.0,
        step: 0.05,
        default: @default_speed
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
        default: 24
      },
      %{
        key: :trail_length,
        label: "Trail length",
        type: :slider,
        min: 10,
        max: 200,
        step: 1,
        default: @default_trail_length
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
      speed: state.speed,
      density: state.density,
      max_particles: state.max_particles,
      trail_length: state.trail_length,
      afterglow: state.afterglow
    }
  end

  def handle_config(config, %State{} = state) do
    raw = coerce_config_atoms(config)

    apply_keys =
      Map.keys(raw)
      |> Enum.map(fn
        :tail_length -> :trail_length
        key -> key
      end)

    normalized =
      state
      |> get_config()
      |> Map.merge(raw)
      |> normalize_mode_config()

    state =
      state
      |> apply_config(Map.take(normalized, apply_keys))
      |> enforce_particle_cap()

    {:noreply, state}
  end

  def now_playing_meta(config) do
    config = normalize_mode_config(config)
    max = Map.get(config, :max_particles, 24)
    density = Map.get(config, :density, 1)
    trail = Map.get(config, :trail_length, @default_trail_length)

    [
      "trail #{trail}",
      "#{max} particles max",
      "density #{density}"
    ]
  end

  def default_max_particles(panel_count) when is_integer(panel_count) and panel_count > 0 do
    max(12, 3 * panel_count)
  end

  def app_init(config) do
    Octopus.App.configure_display(layout: :gapped_panels)
    Octopus.Params.Global.subscribe()

    global_speed = Octopus.Params.Global.speed()
    display_info = Octopus.App.get_display_info()
    installation = Octopus.App.get_installation_info()

    width = trunc(display_info.width)
    height = trunc(display_info.height)
    pitch = installation.panel_width + installation.panel_gap
    panel_count = installation.panel_count

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
        panel_count: panel_count,
        global_speed: global_speed,
        speed: @default_speed,
        density: 1,
        max_particles: default_max_particles(panel_count),
        trail_length: @default_trail_length,
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

  @config_keys [:speed, :density, :max_particles, :trail_length, :afterglow]

  defp apply_config(%State{} = state, config) do
    config
    |> Enum.reduce(state, fn
      {key, value}, acc when key in @config_keys -> Map.put(acc, key, coerce_config_value(key, value))
      _, acc -> acc
    end)
  end

  defp coerce_config_value(:trail_length, value), do: trunc(value)
  defp coerce_config_value(:density, value), do: trunc(value)
  defp coerce_config_value(:max_particles, value), do: trunc(value)
  defp coerce_config_value(:speed, value), do: coerce_float(value)
  defp coerce_config_value(:afterglow, value), do: trunc(value)

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

  defp coerce_float(v) when is_integer(v), do: v * 1.0
  defp coerce_float(v) when is_float(v), do: v
  defp coerce_float(v) when is_binary(v), do: String.to_float(v)
  defp coerce_float(v), do: v
end
