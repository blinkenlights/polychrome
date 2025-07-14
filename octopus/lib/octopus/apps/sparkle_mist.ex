defmodule Octopus.Apps.SparkleMist do
  use Octopus.App, category: :interactive

  alias Octopus.Installation
  alias Octopus.Events.Event.Proximity, as: ProximityEvent
  alias Octopus.Canvas
  alias Octopus.Particles

  def name, do: "✨ Sparkle Mist ✨"

  defmodule State do
    defstruct [:particles, :last_update]
  end

  @fps 60
  @frame_time_ms trunc(1000 / @fps)

  def app_init(_args) do
    Octopus.App.configure_display(layout: :adjacent_panels)

    particles =
      for panel <- 1..Installation.num_panels(),
          sensor <- 0..1,
          into: %{} do
        colors =
          Stream.repeatedly(fn ->
            hue = 360 * (panel - 1) / Installation.num_panels()
            saturation = :rand.uniform() * 25 + 60
            lightness = :rand.uniform() * 25 + 45
            hsl = Chameleon.HSL.new(trunc(hue), trunc(saturation), trunc(lightness))
            %Chameleon.RGB{r: r, g: g, b: b} = Chameleon.convert(hsl, Chameleon.RGB)
            {r, g, b}
          end)

        # Sensor 0 (left): up-right (300°), Sensor 1 (right): up-left (240°)
        angle = if sensor == 0, do: 5 * :math.pi() / 3, else: 4 * :math.pi() / 3

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

    state = %State{
      particles: particles,
      last_update: System.os_time(:millisecond)
    }

    :timer.send_interval(@frame_time_ms, :tick)
    send(self(), :tick)

    {:ok, state}
  end

  def handle_event(%ProximityEvent{} = event, %State{} = state) do
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
          spawn_x = if event.sensor == 0, do: 1, else: Installation.panel_width() - 2
          spawn_y = Installation.panel_height() - 1

          updated_system = Particles.spawn(particle_system, {spawn_x, spawn_y}, 1)
          particles = Map.put(state.particles, key, updated_system)

          %{state | particles: particles}

        _ ->
          state
      end

    {:noreply, state}
  end

  def handle_event(_event, state) do
    {:noreply, state}
  end

  def handle_info(:tick, %State{} = state) do
    state = update_particles(state)

    Canvas.new(
      Installation.num_panels() * Installation.panel_width(),
      Installation.panel_height()
    )
    |> render_particles(state)
    |> update_display()

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
end
