defmodule Octopus.Apps.Rain do
  use Octopus.App, category: :interactive

  require Logger
  alias Octopus.Installation
  alias Octopus.Canvas
  alias Octopus.Particles
  alias Octopus.Events.Event.Proximity, as: ProximityEvent

  def name, do: "⛈️ Rain"

  def compatible?() do
    installation_info = Octopus.App.get_installation_info()

    installation_info.panel_width >= 8 and
      installation_info.panel_height >= 8
  end

  defmodule State do
    defstruct panels: %{}, last_tick: nil, lightning: []
  end

  @fps 60
  @frame_time_ms trunc(1000 / @fps)
  @rain_color_1 {100, 180, 255}
  @rain_color_2 {70, 130, 169}
  @rain_color_3 {145, 200, 228}
  @rain_color_4 {137, 138, 196}
  @rain_color_5 {192, 201, 238}
  @rain_color_6 {116, 155, 194}
  @splash_color {133, 183, 212}
  @proximity_splash_color {255, 0, 255}

  def app_init(_args) do
    Octopus.App.configure_display(layout: :adjacent_panels)
    panel_count = Installation.num_panels()
    panel_width = Installation.panel_width()
    panel_height = Installation.panel_height()

    panels =
      for i <- 0..(panel_count - 1), into: %{} do
        drops = new_rain_system(panel_width, panel_height)
        splash = new_splash_system(panel_width, panel_height)
        proximity_splash = new_proximity_splash_system(panel_width, panel_height)
        {i, {drops, splash, proximity_splash}}
      end

    state = %State{panels: panels, last_tick: System.monotonic_time(:millisecond), lightning: []}
    :timer.send_interval(@frame_time_ms, :tick)
    {:ok, state}
  end

  def handle_event(%ProximityEvent{} = event, %State{panels: panels} = state) do
    panel_height = Installation.panel_height()

    x =
      case Map.get(event, :sensor) do
        1 -> 7
        _ -> 0
      end

    panel_index = event.panel - 1
    {drops, splash, proximity_splash} = Map.get(panels, panel_index)

    proximity_splash =
      Particles.spawn(proximity_splash, {x, panel_height - 1}, 1, color: @proximity_splash_color)

    panels = Map.put(panels, panel_index, {drops, splash, proximity_splash})
    {:noreply, %{state | panels: panels}}
  end

  def handle_event(
        %Octopus.Events.Event.Input{type: :button, action: :press, button: button},
        %State{lightning: lightning} = state
      ) do
    new_lightning = %{panel: button - 1, x: 3, ttl: 16}
    {:noreply, %{state | lightning: [new_lightning | lightning]}}
  end

  def handle_event(event, state) do
    Logger.info("Unhandled event: #{inspect(event)}")
    {:noreply, state}
  end

  def handle_info(
        :tick,
        %State{panels: panels, last_tick: last_tick, lightning: lightning} = state
      ) do
    now = System.monotonic_time(:millisecond)
    # seconds, never 0
    dt = max((now - last_tick) / 1000, 0.001)

    panel_count = Installation.num_panels()
    panel_width = Installation.panel_width()
    panel_height = Installation.panel_height()

    # Update und maybe spawn new drops
    panels =
      panels
      |> Enum.map(fn {i, {drops, splash, proximity_splash}} ->
        drops = maybe_spawn_rain(drops)
        drops = Particles.update(drops, dt)
        splash = maybe_splash(drops, splash)
        splash = Particles.update(splash, dt)
        proximity_splash = Particles.update(proximity_splash, dt)
        {i, {drops, splash, proximity_splash}}
      end)
      |> Enum.into(%{})

    # Update lightning (decrease ttl, remove expired)
    lightning =
      lightning
      |> Enum.map(fn l -> %{l | ttl: l.ttl - 1} end)
      |> Enum.filter(fn l -> l.ttl > 0 end)

    # Draw all panels on a big canvas
    big_canvas = Canvas.new(panel_count * panel_width, panel_height)

    big_canvas =
      Enum.reduce(panels, big_canvas, fn {i, {drops, splash, proximity_splash}}, acc ->
        drops_canvas = Particles.draw(drops, Canvas.new(panel_width, panel_height))
        splash_canvas = Particles.draw(splash, Canvas.new(panel_width, panel_height))
        prox_canvas = Particles.draw(proximity_splash, Canvas.new(panel_width, panel_height))

        acc
        |> Canvas.overlay(drops_canvas, offset: {i * panel_width, 0})
        |> Canvas.overlay(splash_canvas, offset: {i * panel_width, 0})
        |> Canvas.overlay(prox_canvas, offset: {i * panel_width, 0})
      end)

    # Draw lightning
    big_canvas = draw_lightning(big_canvas, lightning, panel_width, panel_height)

    Octopus.App.update_display(big_canvas)
    {:noreply, %{state | panels: panels, last_tick: now, lightning: lightning}}
  end

  defp new_rain_system(width, height) do
    Particles.new(
      width,
      height,
      # downwards
      :math.pi() / 2,
      0.05,
      rain_color(),
      # ttl
      0.5,
      1.2,
      # speed
      18,
      28
    )
  end

  defp new_splash_system(width, height) do
    Particles.new(
      width,
      height,
      # downwards
      :math.pi() / 2,
      0.05,
      [@splash_color],
      # ttl
      0.5,
      1.2,
      # speed
      18,
      28
    )
  end

  defp new_proximity_splash_system(width, height) do
    Particles.new(
      width,
      height,
      # nach oben
      :math.pi() * 1.5,
      # spread
      0.3,
      # knallpink für Debugging
      [@proximity_splash_color],
      # ttl
      0.2,
      0.5,
      # speed
      10,
      20
    )
  end

  defp maybe_spawn_rain(sys) do
    # Spawn new drop with 30% chance per tick
    if :rand.uniform() < 0.3 do
      x = :rand.uniform() * (sys.width - 1)
      Particles.spawn(sys, {x, 0}, 1, colors: rain_color())
    else
      sys
    end
  end

  defp rain_color() do
    Enum.random([@rain_color_1, @rain_color_2, @rain_color_3, @rain_color_4, @rain_color_5, @rain_color_6])
  end

  defp maybe_splash(drops, splash) do
    # If a drop is near the bottom, spawn a splash up with 10% chance
    splash_particles =
      drops.particles
      |> Enum.filter(fn p -> p.y > drops.height - 1 end)
      |> Enum.filter(fn _ -> :rand.uniform() < 0.08 end)

    Enum.reduce(splash_particles, splash, fn p, acc ->
      Particles.spawn(acc, {p.x, acc.height}, 1,
        angle: :math.pi() * 1.5,
        spread: 0.3,
        min_ttl: 0.2,
        max_ttl: 0.5,
        min_speed: 10,
        max_speed: 20
      )
    end)
  end

  defp draw_lightning(canvas, lightning, panel_width, panel_height) do
    Enum.reduce(lightning, canvas, fn l, acc ->
      flash_canvas(canvas)
      x = l.panel * panel_width + l.x
      # Erzeuge Zickzack-Pfad
      {_, path} =
        Enum.reduce(0..(panel_height - 1), {x, []}, fn y, {cur_x, acc_path} ->
          dx = Enum.random([-1, 0, 1])
          next_x = min(max(cur_x + dx, l.panel * panel_width), (l.panel + 1) * panel_width - 1)
          {next_x, [{next_x, y} | acc_path]}
        end)

      Enum.reduce(path, acc, fn {px, py}, c ->
        # Gelber Blitz
        Canvas.put_pixel(c, {px, py}, {255, 241, 23})
      end)
    end)
  end

  # Heller Flash-Effekt für das gesamte Display
  defp flash_canvas(canvas) do
    Canvas.fill(canvas, {247, 242, 200})
  end
end
