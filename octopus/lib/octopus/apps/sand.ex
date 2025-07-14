defmodule Octopus.Apps.Sand do
  use Octopus.App, category: :game

  alias Octopus.Installation
  alias Octopus.Canvas
  alias Octopus.Apps.Sand.Sim
  alias Octopus.Events.Event.Input
  alias Octopus.Particles

  def name, do: "Sand"

  def compatible?() do
    Installation.num_buttons() == Installation.num_panels()
  end

  def app_init(_args) do
    configure_display(layout: :adjacent_panels)

    sims =
      for _ <- 0..(Installation.num_panels() - 1) do
        Octopus.Apps.Sand.Sim.new(Installation.panel_width(), Installation.panel_height())
      end

    particle_systems =
      for _ <- 0..(Installation.num_panels() - 1) do
        Particles.new(
          Installation.panel_width(),
          Installation.panel_height(),
          0,
          0,
          [{255, 255, 255}]
        )
      end

    :timer.send_interval(trunc(1000 / 30), self(), :tick)
    send(self(), :tick)

    {:ok, %{sims: sims, particle_systems: particle_systems}}
  end

  def handle_info(:tick, state) do
    sims = Enum.map(state.sims, &Sim.step(&1))
    particle_systems = Enum.map(state.particle_systems, &Particles.update(&1, 1 / 30.0))

    sim_canvas =
      sims
      |> Enum.map(&Sim.draw(&1, Canvas.new(&1.width, &1.height)))
      |> Enum.reduce(&Canvas.join(&2, &1))

    particle_canvas =
      particle_systems
      |> Enum.map(&Particles.draw(&1, Canvas.new(&1.width, &1.height)))
      |> Enum.reduce(&Canvas.join(&2, &1))

    canvas =
      Enum.reduce(particle_canvas.pixels, sim_canvas, fn {{x, y}, color}, canvas ->
        Canvas.put_pixel(canvas, {x, y}, color)
      end)

    update_display(canvas)

    {:noreply, %{state | sims: sims, particle_systems: particle_systems}}
  end

  def handle_event(%Input{type: :button, action: :press} = _input, state) do
    particles =
      state.sims
      |> Enum.zip(state.particle_systems)
      |> Enum.map(fn {%Sim{} = sim, %Particles{} = particles} ->
        Enum.reduce(sim.particles, particles, fn {{x, y}, {:sand, color}}, particles ->
          Particles.spawn(particles, {x, y}, 1,
            angle: :math.pi() * 1.5,
            spread: 0.25,
            colors: color
          )
        end)
      end)

    sims = Enum.map(state.sims, &Sim.clear/1)

    {:noreply, %{state | sims: sims, particle_systems: particles}}
  end

  def handle_event(_event, state) do
    {:noreply, state}
  end
end
