defmodule Octopus.Apps.Train do
  use Octopus.App, category: :animation
  require Logger

  alias Octopus.{Canvas, Image}
  alias Octopus.Installation
  alias Octopus.Events.Event.Input, as: InputEvent

  @fps 60

  defmodule State do
    defstruct canvas: nil, time: 0, x: 0, acceleration: 0.0, speed: 0.0, stars: []
  end

  def name(), do: "Train Simulator"

  def compatible?() do
    # Check if landscape image is compatible with current installation
    installation = Octopus.App.get_installation_info()

    gapped_width =
      installation.panel_count * installation.panel_width +
        (installation.panel_count - 1) * installation.panel_gap

    # Landscape image is 263px wide - check if it fits in gapped layout
    gapped_width >= 263
  end

  def app_init(_args) do
    Octopus.App.configure_display(layout: :gapped_panels)
    panel_count = Installation.num_panels()
    panel_width = Installation.panel_width()
    panel_height = Installation.panel_height()
    installation = Octopus.App.get_installation_info()
    gapped_width =
      installation.panel_count * installation.panel_width +
        (installation.panel_count - 1) * installation.panel_gap

    image = Image.load("landscape_transparent")

    :timer.send_interval(trunc(1000 / @fps), :tick)
    :timer.send_interval(10_000, :change_acceleration)

    {:ok, %State{canvas: image, time: 0, x: 0, acceleration: 0.1, speed: 0, stars: []}}
  end

  def add_window_corners(canvas) do
    # Use dynamic panel layout instead of hardcoded gap calculation
    display_info = Octopus.App.get_display_info()
    panel_count = display_info.num_panels
    panel_width = display_info.panel_width

    window_locations =
      for panel_id <- 0..(panel_count - 1) do
        {start_x, _end_x} = display_info.panel_range.(panel_id, :x)
        {start_x, 0}
      end

    Enum.reduce(window_locations, canvas, fn {x, y}, canvas ->
      canvas
      |> Canvas.put_pixel({x, y}, {0, 0, 0})
      |> Canvas.put_pixel({x + panel_width - 1, y}, {0, 0, 0})
      |> Canvas.put_pixel({x, y + 7}, {0, 0, 0})
      |> Canvas.put_pixel({x + panel_width - 1, y + 7}, {0, 0, 0})
    end)
  end

  defp day_fraction() do
    {hour, min, sec} = :calendar.local_time() |> elem(1)
    (hour * 3600 + min * 60 + sec) / 86400
  end

  defp sky_color(t) do
    # t: 0.0–1.0, Interpolation zwischen Keyframes
    # Keyframes als Liste
    keyframes = [
      {0.0,   {10, 5, 20}},
      {0.15,  {120, 30, 120}},
      {0.25,  {255, 60, 80}},
      {0.35,  {255, 120, 40}},
      {0.5,   {255, 200, 80}},
      {0.65,  {255, 120, 40}},
      {0.75,  {255, 60, 80}},
      {0.85,  {120, 30, 120}},
      {1.0,   {10, 5, 20}}
    ]
    interpolate_keyframes(keyframes, t)
  end

  defp interpolate_keyframes([{t1, c1}, {t2, c2} | rest], t) when t >= t1 and t <= t2 do
    f = (t - t1) / (t2 - t1)
    lerp_color(c1, c2, f)
  end
  defp interpolate_keyframes([_ | rest], t), do: interpolate_keyframes(rest, t)
  defp interpolate_keyframes([last], _t), do: elem(last, 1)

  defp lerp_color({r1, g1, b1}, {r2, g2, b2}, f) do
    {
      round(r1 + (r2 - r1) * f),
      round(g1 + (g2 - g1) * f),
      round(b1 + (b2 - b1) * f)
    }
  end

  defp update_stars(stars) do
    Enum.reduce(stars, [], fn star, acc ->
      new_x = star.x + star.dx
      new_y = star.y + star.dy
      new_ticks = star.ticks_left - 1
      if new_ticks > 0 and new_x >= 0 and new_y >= 0 do
        [%{star | x: new_x, y: new_y, ticks_left: new_ticks} | acc]
      else
        acc
      end
    end)
  end

  def handle_info(:tick, %State{} = state) do
    installation = Octopus.App.get_installation_info()
    gapped_width =
      installation.panel_count * installation.panel_width +
        (installation.panel_count - 1) * installation.panel_gap
    panel_height = Installation.panel_height()

    # Unabhängige Animation: 1 Tag = 30 Sekunden
    t = :math.fmod(state.time / 150, 1.0)
    sky = sky_color(t)

    bg = Canvas.new(gapped_width, panel_height)
    bg = Canvas.fill(bg, sky)

    # Erst Himmel und PNG/Landschaft rendern
    canvas2 = Canvas.overlay(bg, state.canvas) |> Canvas.translate({trunc(state.x), 0}, true)

    # Dann Sterne auf das finale Canvas zeichnen (bleiben fest am Himmel)
    canvas2 = Enum.reduce(state.stars || [], canvas2, fn star, c ->
      x = round(star.x)
      y = round(star.y)
      rgb = Map.get(star, :color, {255, 255, 0})
      Canvas.put_pixel(c, {x, y}, rgb)
    end)

    canvas2
    |> add_window_corners()
    |> Octopus.App.update_display()

    speed = state.speed + state.acceleration / @fps / 3
    speed = min(10, max(-10, speed))
    speed = speed * (1 / (1 + 0.1 / @fps))

    stars = update_stars(state.stars || [])

    {:noreply, %State{state | time: state.time + 1 / @fps, speed: speed, x: state.x + speed, stars: stars}}
  end

  def handle_info(:change_acceleration, %State{acceleration: 0, speed: speed} = state)
      when speed > 0 do
    {:noreply, %State{state | acceleration: -0.1}}
  end

  def handle_info(:change_acceleration, %State{acceleration: 0, speed: speed} = state)
      when speed <= 0 do
    {:noreply, %State{state | acceleration: 0.1}}
  end

  def handle_info(:change_acceleration, %State{acceleration: 0.1} = state) do
    {:noreply, %State{state | acceleration: 0}}
  end

  def handle_info(:change_acceleration, %State{acceleration: -0.1} = state) do
    {:noreply, %State{state | acceleration: 0}}
  end

  def handle_event(
        %Octopus.Events.Event.Input{type: :button, action: :press, button: button},
        state
      ) do
    panel_id = button - 1
    panel_width = Installation.panel_width()
    panel_gap = Installation.panel_gap()
    panel_start_x = panel_id * (panel_width + panel_gap)
    t = :math.fmod(state.time / 150, 1.0)
    if is_night?(t) do
      # Sternschnuppe wie bisher
      start_x = panel_start_x + (:rand.uniform(panel_width) - 1)
      start_y = 0
      min_angle = :math.pi() * 20 / 180
      max_angle = :math.pi() * 70 / 180
      angle = min_angle + (:rand.uniform() * (max_angle - min_angle))
      speed = 1.0
      direction = if :rand.uniform() < 0.5, do: 1, else: -1
      dx = direction * :math.cos(angle) * speed
      dy = :math.sin(angle) * speed
      ticks_left = 16
      star = %{x: start_x * 1.0, y: start_y * 1.0, dx: dx, dy: dy, ticks_left: ticks_left, color: {255, 255, 0}}
      stars = [star | (state.stars || [])]
      {:noreply, %State{state | stars: stars}}
    else
      # Feuerwerk: mehrere bunte Funken radial
      center_x = panel_start_x + div(panel_width, 2)
      center_y = Enum.random(0..3)
      num_particles = 8
      speed = 1.2
      ticks_left = 12
      new_particles = for i <- 0..(num_particles-1) do
        angle = 2 * :math.pi() * i / num_particles + (:rand.uniform() - 0.5) * 0.3
        dx = :math.cos(angle) * speed * (0.7 + :rand.uniform() * 0.6)
        dy = -:math.sin(angle) * speed * (0.7 + :rand.uniform() * 0.6)
        color = random_color()
        %{x: center_x * 1.0, y: center_y * 1.0, dx: dx, dy: dy, ticks_left: ticks_left, color: color}
      end
      stars = new_particles ++ (state.stars || [])
      {:noreply, %State{state | stars: stars}}
    end
  end

  def handle_event(
        %InputEvent{type: :joystick, joystick: _joystick, direction: :left},
        state
      ) do
    # Go forward (left moves landscape right)
    state = %State{state | acceleration: 0.1}
    {:noreply, state}
  end

  def handle_event(
        %InputEvent{type: :joystick, joystick: _joystick, direction: :right},
        state
      ) do
    # Go backward (right moves landscape left)
    state = %State{state | acceleration: -0.1}
    {:noreply, state}
  end

  def handle_event(
        %InputEvent{type: :joystick, joystick: _joystick, direction: :center},
        state
      ) do
    # Stop accelerating
    state = %State{state | acceleration: 0}
    {:noreply, state}
  end

  def handle_event(%InputEvent{}, state) do
    {:noreply, state}
  end

  def handle_event(_, state) do
    {:noreply, state}
  end

  defp is_night?(t) do
    t < 0.23 or t > 0.77
  end

  defp random_color() do
    # Knallige, zufällige Farbe (mind. 2 Kanäle >= 200, keiner < 80)
    channels = Enum.shuffle([:r, :g, :b])
    vals = [
      Enum.random(200..255),
      Enum.random(200..255),
      Enum.random(80..180)
    ]
    color_map = Enum.zip(channels, vals) |> Enum.into(%{})
    {color_map[:r], color_map[:g], color_map[:b]}
  end
end
