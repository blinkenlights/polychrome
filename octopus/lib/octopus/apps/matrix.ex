defmodule Octopus.Apps.Matrix do
  use Octopus.App, category: :animation

  @mode_presets Module.concat(["Octopus", "AppModePresets"])

  @shimmer_chance 0.03

  defmodule Particle do
    defstruct [:x, :y, :z, :speed, :sign, :age, :fade_age, :tail, :column]
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
      :seconds,
      :occupied_columns,
      :column_cooldowns,
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

      {particles, occupied, cooldowns} =
        Enum.reduce(state.particles, {[], state.occupied_columns, state.column_cooldowns}, fn
          particle, {acc, occupied, cooldowns} ->
            was_above = particle.y < state.height
            updated = advance_particle(particle, state, dt)
            is_above = updated.y < state.height

            {occupied, cooldowns} =
              if state.direction == :classic and was_above and not is_above do
                col = particle.column

                {
                  MapSet.delete(occupied, col),
                  Map.put(cooldowns, col, now + 0.2 + :rand.uniform() * 1.3)
                }
              else
                {occupied, cooldowns}
              end

            if alive?(updated, state) do
              {[updated | acc], occupied, cooldowns}
            else
              {acc, occupied, cooldowns}
            end
        end)

      %State{
        state
        | particles: Enum.reverse(particles),
          particle_count: length(particles),
          occupied_columns: occupied,
          column_cooldowns: prune_cooldowns(cooldowns, now),
          now: now,
          seconds: (state.seconds || 0.0) + dt
      }
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

      %State{state | particles: particles}
    end

    def render(%State{} = state) do
      canvas = Canvas.new(state.width, state.height)
      ctx = render_ctx(state)

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

    defp advance_particle(%Particle{} = particle, state, dt) do
      effective = particle.speed * particle.z * dt
      fade_age = particle.fade_age

      fade_age =
        if fading?(particle, state) do
          fade_age + dt
        else
          fade_age
        end

      case state.direction do
        :classic ->
          %Particle{particle | y: particle.y + effective, age: particle.age + dt, fade_age: fade_age}

        :ring ->
          %Particle{
            particle
            | x: Matrix.wrap_x(particle.x + particle.sign * effective, state.width),
              age: particle.age + dt,
              fade_age: fade_age
          }
      end
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
        y: classic_spawn_y(state.tail_length),
        z: :rand.uniform() * 0.5 + 0.5,
        speed: random_particle_speed(),
        sign: 1,
        age: 0.0,
        fade_age: 0.0,
        tail: new_tail(state.tail_length),
        column: column
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

    defp classic_spawn_y(tail_length) do
      span = tail_length + 2
      -tail_length - 2 + (:rand.uniform(span) - 1)
    end

    defp new_tail(length) do
      Enum.map(1..length, fn _ -> random_flicker() end)
    end

    defp random_flicker, do: :rand.uniform() * 0.25 + 0.75

    defp random_particle_speed do
      if :rand.uniform() > 0.9 do
        18.0
      else
        3.0 + :rand.uniform() * 12.0
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
    |> Map.update(:speed, 1.0, &coerce_float/1)
    |> Map.update(:density, 3, &trunc/1)
    |> Map.update(:max_particles, 200, &trunc/1)
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
      speed: 1.0,
      density: 3,
      max_particles: 200,
      tail_length: 4,
      counterflow: 0.0,
      sway_scale: 0.0,
      sway_speed: 0.5,
      sway_mode: :wobble
    }
  end

  def legacy_mode_config("matrix-ring") do
    %{
      direction: :ring,
      speed: 1.8,
      density: 4,
      max_particles: 200,
      tail_length: 8,
      counterflow: 0.0,
      sway_scale: 0.0,
      sway_speed: 0.5,
      sway_mode: :wobble
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
        max: 3.0,
        step: 0.1,
        default: 1.0
      },
      %{
        key: :density,
        label: "Density",
        type: :slider,
        min: 1,
        max: 10,
        step: 1,
        default: 3
      },
      %{
        key: :max_particles,
        label: "Max particles",
        type: :slider,
        min: 50,
        max: 400,
        step: 10,
        default: 200
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
      sway_mode: state.sway_mode
    }
  end

  def handle_config(config, %State{} = state) do
    config = coerce_config_atoms(config)
    direction_changed = Map.has_key?(config, :direction) && coerce_direction(config.direction) != state.direction

    state =
      state
      |> apply_config(config)
      |> then(fn s -> if direction_changed, do: reset_particles(s), else: s end)

    {:noreply, state}
  end

  def now_playing_meta(config) do
    config = normalize_mode_config(config)
    direction = Map.get(config, :direction, :classic)
    max = Map.get(config, :max_particles, 200)
    density = Map.get(config, :density, 3)
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
  defp format_num(n) when is_integer(n), do: Integer.to_string(n)
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
        speed: 1.0,
        density: 3,
        max_particles: 200,
        direction: :classic,
        tail_length: 4,
        counterflow: 0.0,
        sway_scale: 0.0,
        sway_speed: 0.5,
        sway_mode: :wobble,
        seconds: 0.0,
        occupied_columns: MapSet.new(),
        column_cooldowns: %{},
        now: 0.0
      }
      |> apply_config(normalize_mode_config(config))

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
    state =
      if state.particle_count < state.max_particles do
        State.spawn_particles(state, max(1, trunc(state.density)))
      else
        state
      end

    {:noreply, state}
  end

  def handle_info(:tick, %State{} = state) do
    dt = 1 / 60 * state.speed * state.global_speed
    state = state |> State.update(dt) |> State.render()
    Octopus.App.update_display(state.canvas)
    {:noreply, state}
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
    :sway_mode
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

  defp coerce_sway_mode(mode), do: Octopus.Sway.normalize_mode(mode)

  defp reset_particles(%State{} = state) do
    %{
      state
      | particles: [],
        particle_count: 0,
        occupied_columns: MapSet.new(),
        column_cooldowns: %{}
    }
  end

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
