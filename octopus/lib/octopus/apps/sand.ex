defmodule Octopus.Apps.Sand do
  use Octopus.App, category: :interactive

  alias Octopus.Installation
  alias Octopus.Canvas
  alias Octopus.Apps.Sand.Sim
  alias Octopus.Events.Event.Input
  alias Octopus.Particles

  def name, do: "🏖️ Sand"

  defmodule Panel do
    defstruct [:index, :sim, :particles, :explosion_timeout]

    def new(index, width, height) do
      %Panel{
        index: index,
        sim: Sim.new(width, height),
        particles: Particles.new(width, height, 0, 0, [{255, 255, 255}]),
        explosion_timeout: 0
      }
    end

    def step(%Panel{} = panel) do
      panel
      |> maybe_spawn_sand()
      |> maybe_drain_particles()
      |> update_sim()
    end

    defp maybe_spawn_sand(%Panel{} = panel) do
      if :rand.uniform() > 0.75 do
        x = Enum.random(0..(Installation.panel_width() - 1))
        spawn_pos = {x, -1}

        %Panel{
          panel
          | sim: Sim.put_cell(panel.sim, spawn_pos, {:sand, random_color(panel)})
        }
      else
        panel
      end
    end

    defp maybe_drain_particles(%Panel{} = panel) do
      coords =
        for y <- 0..(Installation.panel_height() - 1),
            x <- 0..(Installation.panel_width() - 1),
            do: {x, y}

      if :rand.uniform() > 0.75 &&
           Enum.all?(coords, fn {x, y} ->
             !Sim.cell_empty?(panel.sim, {x, y})
           end) do
        explode(panel, -5, 0)
      else
        panel
      end
    end

    def draw(%Panel{} = panel) do
      sim_canvas = Sim.draw(panel.sim, Canvas.new(panel.sim.width, panel.sim.height))

      particle_canvas =
        panel.particles
        |> Particles.draw(Canvas.new(panel.particles.width, panel.particles.height))

      Enum.reduce(particle_canvas.pixels, sim_canvas, fn {{x, y}, color}, canvas ->
        Canvas.put_pixel(canvas, {x, y}, color)
      end)
    end

    defp update_sim(%Panel{} = panel) do
      %Panel{
        panel
        | sim: Sim.step(panel.sim),
          particles: Particles.update(panel.particles, 1 / 30.0)
      }
    end

    def handle_button_press(%Panel{} = panel) do
      explode(panel, 30, 50)
    end

    defp explode(%Panel{} = panel, min_force, max_force) do
      sim = panel.sim
      particles = panel.particles

      particles =
        Enum.reduce(sim.particles, particles, fn {{x, y}, {:sand, color}}, particles ->
          Particles.spawn(particles, {x, y}, 1,
            angle: :math.pi() * 1.5,
            spread: 0.15,
            colors: color,
            min_speed: min_force,
            max_speed: max_force
          )
        end)

      sim = Sim.clear(sim)

      %Panel{panel | sim: sim, particles: particles}
    end

    def random_color(%Panel{index: index}, hue_shift \\ 0) do
      hue = rem(trunc(360 * index / Installation.num_panels() + hue_shift), 360)
      saturation = :rand.uniform() * 25 + 60
      lightness = :rand.uniform() * 25 + 45
      hsl = Chameleon.HSL.new(trunc(hue), trunc(saturation), trunc(lightness))
      %Chameleon.RGB{r: r, g: g, b: b} = Chameleon.convert(hsl, Chameleon.RGB)
      {r, g, b}
    end
  end

  def compatible?() do
    Installation.num_buttons() == Installation.num_panels()
  end

  def app_init(_args) do
    configure_display(layout: :adjacent_panels)

    panels =
      for i <- 0..(Installation.num_panels() - 1), into: %{} do
        {i, Panel.new(i, Installation.panel_width(), Installation.panel_height())}
      end

    :timer.send_interval(trunc(1000 / 30), self(), :tick)
    send(self(), :tick)

    {:ok, %{panels: panels}}
  end

  def handle_info(:tick, state) do
    panels = Map.new(state.panels, fn {i, panel} -> {i, Panel.step(panel)} end)

    canvas =
      panels
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(&elem(&1, 1))
      |> Enum.map(&Panel.draw/1)
      |> Enum.reduce(&Canvas.join(&2, &1))

    update_display(canvas)

    {:noreply, %{state | panels: panels}}
  end

  def handle_event(%Input{type: :button, action: :press} = input, state) do
    index = input.button - 1
    panels = Map.update(state.panels, index, nil, &Panel.handle_button_press/1)
    {:noreply, %{state | panels: panels}}
  end

  def handle_event(_event, state) do
    {:noreply, state}
  end
end
