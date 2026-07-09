defmodule Octopus.Apps.SparkleMist do
  use Octopus.App, category: :interactive
  use Octopus.Params, prefix: :sparkle_mist

  @mode_presets Module.concat(["Octopus", "AppModePresets"])

  alias Octopus.Installation
  alias Octopus.Canvas
  alias Octopus.Particles
  alias Octopus.Radar
  alias Octopus.Radar.Frame
  alias Octopus.Radar.PanelMapping

  @fps 60
  @frame_time_ms trunc(1000 / @fps)

  @ring_inner_m 4.0
  @ring_outer_m 10.0
  @track_stale_ms 500
  @trickle_cooldown_ms 400
  @burst_count 25

  def name, do: "✨ Sparkle Mist ✨"

  def list_modes do
    apply(@mode_presets, :list_modes, [__MODULE__])
  end

  def mode_config(mode_id) do
    apply(@mode_presets, :config_for, [__MODULE__, mode_id]) ||
      legacy_mode_config(apply(@mode_presets, :mode_slug, [mode_id]))
  end

  def builtin_presets do
    [
      %{
        slug: "mist",
        name: "Sparkle Mist",
        accent_color: "#9B59B6",
        config: legacy_mode_config("mist")
      }
    ]
  end

  def legacy_mode_config("mist") do
    %{
      foreground_hue: 25,
      background_hue_a: 200,
      background_hue_b: 170,
      background_sat_a: 100,
      background_sat_b: 85,
      expr: "noise(sin(x/26-t+y/40),x*0.01,y*0.01)",
      particle_speed_scale: 1.0,
      background_speed: 5.0
    }
  end

  def legacy_mode_config(_), do: %{}

  def mode_tweakables(mode_id) do
    mode_tweakables_for(apply(@mode_presets, :mode_slug, [mode_id]))
  end

  def mode_tweakables_for("mist") do
    [
      %{
        key: :foreground_hue,
        label: "Spark hue",
        type: :slider,
        min: 0,
        max: 359,
        step: 1,
        default: 25
      },
      %{
        key: :background_speed,
        label: "Mist speed",
        type: :slider,
        min: 0.1,
        max: 10.0,
        step: 0.1,
        default: 5.0
      },
      %{
        key: :particle_speed_scale,
        label: "Spark intensity",
        type: :slider,
        min: 0.1,
        max: 5.0,
        step: 0.1,
        default: 1.0
      },
      %{
        key: :background_hue_a,
        label: "Background hue",
        type: :slider,
        min: 0,
        max: 359,
        step: 1,
        default: 200
      }
    ]
  end

  def mode_tweakables_for(_), do: []

  def now_playing_meta(config) do
    foreground_hue = Map.get(config, :foreground_hue, 25)
    background_speed = Map.get(config, :background_speed, 5.0)
    particle_speed_scale = Map.get(config, :particle_speed_scale, 1.0)
    background_hue_a = Map.get(config, :background_hue_a, 200)

    [
      "spark hue #{foreground_hue}",
      "mist speed #{format_num(background_speed)}",
      "intensity #{format_num(particle_speed_scale)}",
      "bg hue #{background_hue_a}",
      "Walk the ring for sparkles"
    ]
  end

  def compatible? do
    installation = Octopus.App.get_installation_info()

    installation.panel_width >= 8 and installation.panel_height >= 8
  end

  defmodule State do
    defstruct [
      :particles,
      :last_update,
      :parsed_expr,
      :color_a,
      :color_b,
      :foreground_hue,
      :background_hue_a,
      :background_hue_b,
      :background_sat_a,
      :background_sat_b,
      :expr,
      :particle_speed_scale,
      :background_speed,
      :track_registry,
      :track_motion,
      :last_trickle
    ]
  end

  def config_schema() do
    %{
      foreground_hue: {"Foreground Hue", :int, %{default: 25, min: 0, max: 359}},
      background_hue_a: {"Background Hue A", :int, %{default: 200, min: 0, max: 359}},
      background_hue_b: {"Background Hue B", :int, %{default: 170, min: 0, max: 359}},
      background_sat_a: {"Background Saturation A", :int, %{default: 100, min: 0, max: 100}},
      background_sat_b: {"Background Saturation B", :int, %{default: 85, min: 0, max: 100}},
      expr:
        {"Background Expression", :string, %{default: "noise(sin(x/26-t+y/40),x*0.01,y*0.01)"}},
      particle_speed_scale: {"Particle Speed Scale", :float, %{default: 1.0, min: 0.1, max: 5.0}},
      background_speed: {"Background Speed", :float, %{default: 5.0, min: 0.1, max: 10.0}}
    }
  end

  def get_config(%State{} = state) do
    %{
      foreground_hue: state.foreground_hue,
      background_hue_a: state.background_hue_a,
      background_hue_b: state.background_hue_b,
      background_sat_a: state.background_sat_a,
      background_sat_b: state.background_sat_b,
      expr: state.expr,
      particle_speed_scale: state.particle_speed_scale,
      background_speed: state.background_speed
    }
  end

  def handle_config(config, %State{} = state) do
    {:noreply, apply_config(state, config)}
  end

  def app_init(config) do
    Octopus.App.configure_display(
      layout: :adjacent_panels,
      supports_rgb: true,
      supports_grayscale: true,
      merge_rgbw: true
    )

    Radar.subscribe()

    panel_count = Installation.num_panels()
    panel_width = Installation.panel_width()
    panel_height = Installation.panel_height()

    merged = Map.merge(legacy_mode_config("mist"), Map.new(config))
    foreground_hue = Map.get(merged, :foreground_hue, 25)

    particles =
      for panel <- 0..(panel_count - 1), into: %{} do
        {panel, new_panel_particles(foreground_hue, panel_width, panel_height)}
      end

    state = %State{
      particles: particles,
      last_update: System.os_time(:millisecond),
      track_registry: %{},
      track_motion: %{},
      last_trickle: %{}
    }

    :timer.send_interval(@frame_time_ms, :tick)
    {:ok, apply_config(state, config)}
  end

  def handle_info({:radar_frame, _device_id, %Frame{tracks: tracks}}, state) do
    now = :erlang.monotonic_time(:millisecond)

    track_registry =
      Enum.reduce(tracks, state.track_registry, fn track, acc ->
        person = %{
          id: track.id,
          x: track.x,
          y: track.y,
          vx: track.vx,
          vy: track.vy
        }

        Map.put(acc, track.id, {person, now})
      end)

    {:noreply, %{state | track_registry: track_registry}}
  end

  def handle_info(:tick, %State{} = state) do
    radar_now = :erlang.monotonic_time(:millisecond)
    now = System.os_time(:millisecond)

    people = active_people(state.track_registry, radar_now, @track_stale_ms)

    panel_count = Installation.num_panels()
    panel_width = Installation.panel_width()
    panel_height = Installation.panel_height()

    {particles, track_motion, last_trickle} =
      apply_radar_sparkles(
        people,
        state.particles,
        state.track_motion,
        state.last_trickle,
        now,
        panel_count,
        panel_width,
        panel_height,
        state.particle_speed_scale
      )

    state = %{
      state
      | particles: particles,
        track_motion: track_motion,
        last_trickle: last_trickle
    }

    state = update_particles(state)

    empty_canvas =
      Canvas.new(
        panel_count * panel_width,
        panel_height
      )

    empty_canvas
    |> draw_pixel_fun(
      state.last_update / 1000.0 / state.background_speed,
      state.color_a,
      state.color_b,
      state.parsed_expr
    )
    |> render_particles(state)
    |> update_display(:rgb)

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp active_people(track_registry, now, stale_ms) do
    track_registry
    |> Enum.filter(fn {_id, {_person, seen_at}} -> now - seen_at <= stale_ms end)
    |> Enum.map(fn {_id, {person, _seen_at}} -> person end)
  end

  defp apply_radar_sparkles(
         people,
         particles,
         track_motion,
         last_trickle,
         now,
         panel_count,
         panel_width,
         panel_height,
         speed_scale
       ) do
    active_ids = MapSet.new(Enum.map(people, & &1.id))
    spawn_y = panel_height - 1

    {particles, track_motion, last_trickle} =
      Enum.reduce(people, {particles, track_motion, last_trickle}, fn person,
                                                                        {particles_acc, motion_acc,
                                                                         trickle_acc} ->
        in_ring = PanelMapping.in_ring?(person, @ring_inner_m, @ring_outer_m)
        prev = Map.get(motion_acc, person.id, %{in_ring: in_ring})
        ring_entry = in_ring and not prev.in_ring
        motion_acc = Map.put(motion_acc, person.id, %{in_ring: in_ring})

        if in_ring do
          {panel_index, spawn_x, radius} =
            PanelMapping.track_to_splash_pos(person, panel_count, panel_width)

          {min_speed, max_speed} = scale_radius_to_speed(radius, speed_scale)
          angle = sparkle_angle(spawn_x, panel_width)
          trickle_key = {person.id, panel_index}

          cond do
            ring_entry ->
              system = Map.fetch!(particles_acc, panel_index)

              updated =
                Particles.spawn(system, {spawn_x, spawn_y}, @burst_count,
                  min_speed: min_speed,
                  max_speed: max_speed,
                  angle: angle
                )

              particles_acc = Map.put(particles_acc, panel_index, updated)
              trickle_acc = Map.put(trickle_acc, trickle_key, now)
              {particles_acc, motion_acc, trickle_acc}

            recently_trickled?(trickle_acc, trickle_key, now) ->
              {particles_acc, motion_acc, trickle_acc}

            true ->
              speed = PanelMapping.track_speed(person)
              trickle_count = trickle_count(radius, speed)
              system = Map.fetch!(particles_acc, panel_index)

              updated =
                Particles.spawn(system, {spawn_x, spawn_y}, trickle_count,
                  min_speed: min_speed,
                  max_speed: max_speed,
                  angle: angle
                )

              particles_acc = Map.put(particles_acc, panel_index, updated)
              trickle_acc = Map.put(trickle_acc, trickle_key, now)
              {particles_acc, motion_acc, trickle_acc}
          end
        else
          {particles_acc, motion_acc, trickle_acc}
        end
      end)

    track_motion = Map.take(track_motion, MapSet.to_list(active_ids))

    last_trickle =
      Map.filter(last_trickle, fn {{track_id, _panel}, _ts} ->
        MapSet.member?(active_ids, track_id)
      end)

    {particles, track_motion, last_trickle}
  end

  defp recently_trickled?(last_trickle, key, now) do
    case Map.get(last_trickle, key) do
      nil -> false
      ts -> now - ts < @trickle_cooldown_ms
    end
  end

  defp trickle_count(radius, speed) do
    radial =
      (radius - @ring_inner_m) / (@ring_outer_m - @ring_inner_m)
      |> clamp01()

    trunc(5 + radial * 2 + speed * 1.5) |> max(5) |> min(8)
  end

  defp scale_radius_to_speed(radius_m, scale) do
    clamped = radius_m |> max(@ring_inner_m) |> min(@ring_outer_m)

    normalized =
      (clamped - @ring_inner_m) / (@ring_outer_m - @ring_inner_m)
      |> clamp01()

    min_speed = (15 + normalized * 20) * scale
    max_speed = (30 + normalized * 15) * scale
    {min_speed, max_speed}
  end

  defp sparkle_angle(spawn_x, panel_width) do
    if spawn_x < div(panel_width, 2) do
      25 * :math.pi() / 18
    else
      29 * :math.pi() / 18
    end
  end

  defp new_panel_particles(foreground_hue, panel_width, panel_height) do
    colors =
      Stream.repeatedly(fn ->
        saturation = :rand.uniform() * 25 + 60
        lightness = :rand.uniform() * 25 + 45
        hsl = Chameleon.HSL.new(trunc(foreground_hue), trunc(saturation), trunc(lightness))
        %Chameleon.RGB{r: r, g: g, b: b} = Chameleon.convert(hsl, Chameleon.RGB)
        {r, g, b}
      end)

    Particles.new(
      panel_width,
      panel_height,
      27 * :math.pi() / 18,
      0.05,
      colors,
      1.0,
      2.5,
      25,
      50
    )
  end

  defp apply_config(%State{} = state, config) do
    config = coerce_config_atoms(config)
    defaults = legacy_mode_config("mist")

    foreground_hue =
      Map.get(config, :foreground_hue, Map.get(state, :foreground_hue) || defaults.foreground_hue)

    background_hue_a =
      Map.get(config, :background_hue_a, Map.get(state, :background_hue_a) || defaults.background_hue_a)

    background_hue_b =
      Map.get(config, :background_hue_b, Map.get(state, :background_hue_b) || defaults.background_hue_b)

    background_sat_a =
      Map.get(config, :background_sat_a, Map.get(state, :background_sat_a) || defaults.background_sat_a)

    background_sat_b =
      Map.get(config, :background_sat_b, Map.get(state, :background_sat_b) || defaults.background_sat_b)

    expr = Map.get(config, :expr, Map.get(state, :expr) || defaults.expr)

    particle_speed_scale =
      Map.get(
        config,
        :particle_speed_scale,
        Map.get(state, :particle_speed_scale) || defaults.particle_speed_scale
      )

    background_speed =
      Map.get(config, :background_speed, Map.get(state, :background_speed) || defaults.background_speed)

    effective = %{
      foreground_hue: foreground_hue,
      background_hue_a: background_hue_a,
      background_hue_b: background_hue_b,
      background_sat_a: background_sat_a,
      background_sat_b: background_sat_b,
      expr: expr,
      particle_speed_scale: particle_speed_scale,
      background_speed: background_speed
    }

    parsed_expr =
      if expr != state.expr || is_nil(state.parsed_expr) do
        case Octopus.Apps.PixelFun.Program.parse(expr) do
          {:ok, parsed} -> parsed
          {:error, _} -> state.parsed_expr
        end
      else
        state.parsed_expr
      end

    {color_a, color_b} = background_colors(effective)

    %State{
      state
      | foreground_hue: foreground_hue,
        background_hue_a: background_hue_a,
        background_hue_b: background_hue_b,
        background_sat_a: background_sat_a,
        background_sat_b: background_sat_b,
        expr: expr,
        parsed_expr: parsed_expr,
        particle_speed_scale: particle_speed_scale,
        background_speed: background_speed,
        color_a: color_a,
        color_b: color_b
    }
  end

  defp coerce_config_atoms(config) when is_map(config) do
    Map.new(config, fn
      {k, v} when is_binary(k) -> {String.to_existing_atom(k), v}
      {k, v} -> {k, v}
    end)
  rescue
    ArgumentError ->
      Map.new(config, fn {k, v} -> {String.to_atom(k), v} end)
  end

  defp background_colors(config) do
    color_a = Chameleon.HSV.new(config.background_hue_a, config.background_sat_a, 100)
    color_b = Chameleon.HSV.new(config.background_hue_b, config.background_sat_b, 100)
    {color_a, color_b}
  end

  defp format_num(n) when is_float(n), do: :erlang.float_to_binary(n, decimals: 1)
  defp format_num(n) when is_integer(n), do: Integer.to_string(n)

  defp update_particles(%State{} = state) do
    now = System.os_time(:millisecond)
    dt = (now - state.last_update) / 1000.0 / 3.0

    particles =
      state.particles
      |> Enum.map(fn {key, particle_system} ->
        {key, Particles.update(particle_system, dt)}
      end)
      |> Enum.into(%{})

    %{state | particles: particles, last_update: now}
  end

  defp render_particles(canvas, %State{} = state) do
    panel_width = Installation.panel_width()

    Enum.reduce(state.particles, canvas, fn {panel, particle_system}, acc_canvas ->
      dx = panel * panel_width
      Particles.draw(particle_system, acc_canvas, {dx, 0})
    end)
  end

  defp clamp01(value), do: value |> max(0.0) |> min(1.0)

  defp draw_pixel_fun(canvas, t, color_a, color_b, parsed_expr) do
    for y <- 0..(canvas.height - 1),
        x <- 0..(canvas.width - 1),
        i = x + y * canvas.width,
        into: canvas do
      {{x, y},
       Octopus.Apps.PixelFun.pixels(
         parsed_expr,
         x,
         y,
         i,
         t,
         color_a,
         color_b,
         &lerp_colors/3
       )}
    end
  end

  defp lerp_colors(%Chameleon.HSV{} = a, %Chameleon.HSV{} = b, value) do
    cond do
      value > 0 ->
        hsv = %Chameleon.HSV{a | s: 70, v: trunc(100 * value) |> max(0) |> min(100)}
        fast_hsv_to_rgb(hsv.h, hsv.s, hsv.v)

      value < 0 ->
        hsv = %Chameleon.HSV{b | s: 70, v: trunc(100 * -value) |> max(0) |> min(100)}
        fast_hsv_to_rgb(hsv.h, hsv.s, hsv.v)

      true ->
        {0, 0, 0}
    end
  end

  defp fast_hsv_to_rgb(h, s, v) do
    h_norm = rem(h, 360) / 60.0
    s_norm = s / 100.0
    v_norm = v / 100.0

    c = v_norm * s_norm
    x = c * (1 - abs(:math.fmod(h_norm, 2.0) - 1))
    m = v_norm - c

    {r, g, b} =
      cond do
        h_norm < 1 -> {c, x, 0}
        h_norm < 2 -> {x, c, 0}
        h_norm < 3 -> {0, c, x}
        h_norm < 4 -> {0, x, c}
        h_norm < 5 -> {x, 0, c}
        true -> {c, 0, x}
      end

    {
      trunc((r + m) * 255) |> max(0) |> min(255),
      trunc((g + m) * 255) |> max(0) |> min(255),
      trunc((b + m) * 255) |> max(0) |> min(255)
    }
  end

  def profile_draw_pixel_fun() do
    canvas = Canvas.new(8 * 12, 8)
    {:ok, parsed_expr} = Octopus.Apps.PixelFun.Program.parse("sin(x/26-t+y/40)")
    color_a = Chameleon.HSV.new(200, 100, 100)
    color_b = Chameleon.HSV.new(170, 85, 100)
    t = 1.0

    for _i <- 1..10 do
      draw_pixel_fun(canvas, t, color_a, color_b, parsed_expr)
    end

    :ok
  end
end
