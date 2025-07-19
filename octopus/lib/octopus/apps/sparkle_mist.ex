defmodule Octopus.Apps.SparkleMist do
  use Octopus.App, category: :interactive
  use Octopus.Params, prefix: :sparkle_mist

  require Logger

  alias Octopus.Installation
  alias Octopus.Events.Event.Proximity, as: ProximityEvent
  alias Octopus.Events.Event.Input, as: InputEvent
  alias Octopus.Canvas
  alias Octopus.Particles
  alias Octopus.PerlinNoise

  @fps 60
  @frame_time_ms trunc(1000 / @fps)
  # Currently unused, kept for potential future use
  @panel_wait_duration_ms 2000

  def name, do: "✨ Sparkle Mist ✨"

  defmodule State do
    defstruct [
      :particles,
      :last_update,
      :noise,
      :last_proximity,
      :color_a,
      :color_b,

      # Config parameters
      :foreground_hue,
      :background_hue_a,
      :background_hue_b,
      :background_sat_a,
      :background_sat_b,
      :expr,
      :parsed_expr,
      :particle_speed_scale,
      :background_speed
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
    hue_a = config.background_hue_a
    hue_b = config.background_hue_b
    sat_a = config.background_sat_a
    sat_b = config.background_sat_b
    color_a = Chameleon.HSV.new(hue_a, sat_a, 100)
    color_b = Chameleon.HSV.new(hue_b, sat_b, 100)

    parsed_expr =
      case Octopus.Apps.PixelFun.Program.parse(config.expr) do
        {:ok, expr} -> expr
        {:error, _} -> state.parsed_expr
      end

    new_state = %State{
      state
      | foreground_hue: config.foreground_hue,
        background_hue_a: config.background_hue_a,
        background_hue_b: config.background_hue_b,
        background_sat_a: config.background_sat_a,
        background_sat_b: config.background_sat_b,
        expr: config.expr,
        parsed_expr: parsed_expr,
        particle_speed_scale: config.particle_speed_scale,
        background_speed: config.background_speed,
        color_a: color_a,
        color_b: color_b
    }

    {:noreply, new_state}
  end

  def app_init(config) do
    Octopus.App.configure_display(
      layout: :adjacent_panels,
      supports_rgb: true,
      supports_grayscale: true,
      merge_rgbw: true
    )

    subscribe_to_button_events()

    particles =
      for panel <- 1..Installation.num_panels(),
          sensor <- 0..1,
          into: %{} do
        colors =
          Stream.repeatedly(fn ->
            # base_hue = 360 * (panel - 1) / Installation.num_panels()
            base_hue = config.foreground_hue
            hue = base_hue
            # hue = if sensor == 0, do: base_hue, else: rem(trunc(base_hue + 180), 360)
            saturation = :rand.uniform() * 25 + 60
            lightness = :rand.uniform() * 25 + 45
            hsl = Chameleon.HSL.new(trunc(hue), trunc(saturation), trunc(lightness))
            %Chameleon.RGB{r: r, g: g, b: b} = Chameleon.convert(hsl, Chameleon.RGB)
            {r, g, b}
          end)

        # Sensor 0 (left): up-right (290°), Sensor 1 (right): up-left (250°)
        angle = if sensor == 0, do: 29 * :math.pi() / 18, else: 25 * :math.pi() / 18

        particle_system =
          Particles.new(
            Installation.panel_width(),
            Installation.panel_height(),
            angle,
            0.05,
            colors,
            1.0,
            2.5,
            25,
            50
          )

        {{panel, sensor}, particle_system}
      end

    last_proximity =
      for panel <- 1..Installation.num_panels(), into: %{} do
        {panel, nil}
      end

    # Use config values for color scheme
    hue_a = config.background_hue_a
    hue_b = config.background_hue_b
    sat_a = config.background_sat_a
    sat_b = config.background_sat_b
    color_a = Chameleon.HSV.new(hue_a, sat_a, 100)
    color_b = Chameleon.HSV.new(hue_b, sat_b, 100)

    {:ok, parsed_expr} = Octopus.Apps.PixelFun.Program.parse(config.expr)

    state = %State{
      particles: particles,
      noise: PerlinNoise.new(),
      last_update: System.os_time(:millisecond),
      last_proximity: last_proximity,
      color_a: color_a,
      color_b: color_b,
      foreground_hue: config.foreground_hue,
      background_hue_a: config.background_hue_a,
      background_hue_b: config.background_hue_b,
      background_sat_a: config.background_sat_a,
      background_sat_b: config.background_sat_b,
      expr: config.expr,
      parsed_expr: parsed_expr,
      particle_speed_scale: config.particle_speed_scale,
      background_speed: config.background_speed
    }

    :timer.send_interval(@frame_time_ms, :tick)

    {:ok, state}
  end

  def handle_event(%ProximityEvent{} = event, %State{} = state) do
    Logger.debug("Proximity Event #{event.panel} #{event.sensor} #{event.distance_combined}")

    now = System.os_time(:millisecond)
    last_proximity = Map.put(state.last_proximity, event.panel, now)

    probability = 1.0

    state =
      case :rand.uniform() do
        random when random < probability ->
          key = {event.panel, event.sensor}
          particle_system = Map.get(state.particles, key)

          # Spawn from corners based on sensor: 1 = left, 0 = right
          spawn_x = if event.sensor == 1, do: 0, else: Installation.panel_width() - 1
          spawn_y = Installation.panel_height() - 1

          {min_speed, max_speed} =
            scale_distance_to_speed(event.distance_combined, state.particle_speed_scale)

          updated_system =
            Particles.spawn(particle_system, {spawn_x, spawn_y}, 25,
              min_speed: min_speed,
              max_speed: max_speed
            )

          particles = Map.put(state.particles, key, updated_system)

          %{state | particles: particles, last_proximity: last_proximity}

        _ ->
          %{state | last_proximity: last_proximity}
      end

    {:noreply, state}
  end

  def handle_event(
        %InputEvent{type: :button, action: :press, button: button_number},
        %State{} = state
      ) do
    Logger.debug("Input Event Button #{button_number}")

    colors =
      Stream.repeatedly(fn ->
        # base_hue = 360 * (panel - 1) / Installation.num_panels()
        base_hue = 55
        hue = base_hue
        # hue = if sensor == 0, do: base_hue, else: rem(trunc(base_hue + 180), 360)
        saturation = :rand.uniform() * 25 + 60
        lightness = :rand.uniform() * 25 + 45
        hsl = Chameleon.HSL.new(trunc(hue), trunc(saturation), trunc(lightness))
        %Chameleon.RGB{r: r, g: g, b: b} = Chameleon.convert(hsl, Chameleon.RGB)
        {r, g, b}
      end)

    # Use sensor 0 (left) particle system for button presses
    key = {button_number, 0}

    updated_system =
      Map.get(state.particles, key)
      |> Particles.spawn({Installation.panel_width() / 2, Installation.panel_height()}, 25,
        angle: :math.pi() * 1.5,
        min_speed: 25,
        max_speed: 50,
        colors: colors
      )

    particles = Map.put(state.particles, key, updated_system)

    {:noreply, %{state | particles: particles}}
  end

  def handle_event(_event, state) do
    Logger.debug("Sparkle Mist: Unhandled event")
    {:noreply, state}
  end

  def handle_info(:tick, %State{} = state) do
    state = update_particles(state)

    empty_canvas =
      Canvas.new(
        Installation.num_panels() * Installation.panel_width(),
        Installation.panel_height()
      )

    empty_canvas
    |> draw_pixel_fun(
      state.last_update / 1000.0 / state.background_speed,
      state.color_a,
      state.color_b,
      state.parsed_expr
    )
    # |> clear_panels_with_particles(state)
    |> render_particles(state)
    |> update_display(:rgb)

    # PerlinNoise.draw(state.noise, empty_canvas, state.last_update / 1000.0)
    # # |> dimm_panels(0.5)
    # |> update_display(:grayscale)

    {:noreply, state}
  end

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
    Enum.reduce(state.particles, canvas, fn {{panel, _sensor}, particle_system}, acc_canvas ->
      dx = (panel - 1) * Installation.panel_width()
      dy = 0

      Particles.draw(particle_system, acc_canvas, {dx, dy})
    end)
  end

  # defp clear_panels_with_particles(canvas, %State{} = state) do
  #   now = System.os_time(:millisecond)

  #   panels_to_clean =
  #     state.last_proximity
  #     |> Enum.filter(fn {_panel, last_proximity} ->
  #       last_proximity != nil and now - last_proximity <= @panel_wait_duration_ms
  #     end)
  #     |> Enum.map(fn {panel, _} -> panel end)

  #   Enum.reduce(panels_to_clean, canvas, fn panel, acc_canvas ->
  #     start_x = (panel - 1) * Installation.panel_width()
  #     end_x = start_x + Installation.panel_width() - 1
  #     end_y = Installation.panel_height() - 1

  #     Canvas.clear_rect(acc_canvas, {start_x, 0}, {end_x, end_y})
  #   end)
  # end

  defp scale_distance_to_speed(distance, scale) do
    clamped_distance = max(400, min(2000, distance))

    normalized = (2000 - clamped_distance) / (2000 - 400)

    min_speed = (15 + normalized * (35 - 15)) * scale
    max_speed = (30 + normalized * (45 - 30)) * scale

    {min_speed, max_speed}
  end

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
        # Use color A, adjust brightness based on value, hardcode saturation at 70%
        hsv = %Chameleon.HSV{a | s: 70, v: trunc(100 * value) |> max(0) |> min(100)}
        fast_hsv_to_rgb(hsv.h, hsv.s, hsv.v)

      value < 0 ->
        # Use color B, adjust brightness based on absolute value, hardcode saturation at 70%
        hsv = %Chameleon.HSV{b | s: 70, v: trunc(100 * -value) |> max(0) |> min(100)}
        fast_hsv_to_rgb(hsv.h, hsv.s, hsv.v)

      true ->
        # Black
        {0, 0, 0}
    end
  end

  defp fast_hsv_to_rgb(h, s, v) do
    # Normalize inputs
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

    # Convert to 0-255 range and ensure integer values
    {
      trunc((r + m) * 255) |> max(0) |> min(255),
      trunc((g + m) * 255) |> max(0) |> min(255),
      trunc((b + m) * 255) |> max(0) |> min(255)
    }
  end

  # Profile target function for tprof
  def profile_draw_pixel_fun() do
    # Create test canvas and parameters similar to real usage
    # Typical total canvas size
    canvas = Canvas.new(8 * 12, 8)
    {:ok, parsed_expr} = Octopus.Apps.PixelFun.Program.parse("sin(x/26-t+y/40)")
    color_a = Chameleon.HSV.new(200, 100, 100)
    color_b = Chameleon.HSV.new(170, 85, 100)
    t = 1.0

    # Run multiple iterations to get meaningful data
    for _i <- 1..10 do
      draw_pixel_fun(canvas, t, color_a, color_b, parsed_expr)
    end

    :ok
  end
end
