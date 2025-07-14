defmodule Octopus.Apps.SparkleMist do
  use Octopus.App, category: :interactive

  alias Octopus.Installation
  alias Octopus.Events.Event.Proximity, as: ProximityEvent
  alias Octopus.Canvas
  alias Octopus.Particles
  alias Octopus.PerlinNoise

  def name, do: "✨ Sparkle Mist ✨"

  defmodule State do
    defstruct [:particles, :last_update, :noise, :last_proximity]
  end

  @fps 60
  @frame_time_ms trunc(1000 / @fps)
  @panel_wait_duration_ms 2000

  def app_init(_args) do
    Octopus.App.configure_display(
      layout: :adjacent_panels,
      supports_rgb: true,
      supports_grayscale: true,
      merge_rgbw: true
    )

    particles =
      for panel <- 1..Installation.num_panels(),
          sensor <- 0..1,
          into: %{} do
        colors =
          Stream.repeatedly(fn ->
            base_hue = 360 * (panel - 1) / Installation.num_panels()
            hue = if sensor == 0, do: base_hue, else: rem(trunc(base_hue + 180), 360)
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
            35
          )

        {{panel, sensor}, particle_system}
      end

    last_proximity =
      for panel <- 1..Installation.num_panels(), into: %{} do
        {panel, nil}
      end

    state = %State{
      particles: particles,
      noise: PerlinNoise.new(),
      last_update: System.os_time(:millisecond),
      last_proximity: last_proximity
    }

    :timer.send_interval(@frame_time_ms, :tick)
    send(self(), :tick)

    {:ok, state}
  end

  def handle_event(%ProximityEvent{} = event, %State{} = state) do
    now = System.os_time(:millisecond)
    last_proximity = Map.put(state.last_proximity, event.panel, now)

    probability =
      case event.distance_combined do
        distance when distance <= 300 -> 1.0
        distance when distance >= 2000 -> 0.2
        distance -> 0.2 + 0.8 * (2000 - distance) / 1700
      end

    state =
      case :rand.uniform() do
        random when random < probability ->
          key = {event.panel, event.sensor}
          particle_system = Map.get(state.particles, key)

          # Spawn from corners based on sensor: 0 = left, 1 = right
          spawn_x = if event.sensor == 0, do: 0, else: Installation.panel_width() - 1
          spawn_y = Installation.panel_height() - 1

          updated_system = Particles.spawn(particle_system, {spawn_x, spawn_y}, 1)
          particles = Map.put(state.particles, key, updated_system)

          %{state | particles: particles, last_proximity: last_proximity}

        _ ->
          %{state | last_proximity: last_proximity}
      end

    {:noreply, state}
  end

  def handle_event(_event, state) do
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
    |> render_particles(state)
    |> update_display(:rgb)

    PerlinNoise.draw(state.noise, empty_canvas, state.last_update / 1000.0)
    |> clear_panels_with_particles(state)
    |> update_display(:grayscale)

    {:noreply, state}
  end

  defp update_particles(%State{} = state) do
    now = System.os_time(:millisecond)
    dt = (now - state.last_update) / 1000.0

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

  defp clear_panels_with_particles(canvas, %State{} = state) do
    now = System.os_time(:millisecond)

    panels_to_clean =
      state.last_proximity
      |> Enum.filter(fn {_panel, last_proximity} ->
        last_proximity != nil and now - last_proximity <= @panel_wait_duration_ms
      end)
      |> Enum.map(fn {panel, _} -> panel end)

    Enum.reduce(panels_to_clean, canvas, fn panel, acc_canvas ->
      start_x = (panel - 1) * Installation.panel_width()
      end_x = start_x + Installation.panel_width() - 1
      end_y = Installation.panel_height() - 1

      Canvas.clear_rect(acc_canvas, {start_x, 0}, {end_x, end_y})
    end)
  end
end
