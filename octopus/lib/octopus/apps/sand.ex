defmodule Octopus.Apps.Sand do
  use Octopus.App, category: :game

  alias Octopus.Installation
  alias Octopus.Canvas
  alias Octopus.Apps.Sand.Sim
  alias Octopus.Events.Event.Input
  alias Octopus.Particles

  def name, do: "🏖️ Sand"

  defmodule Panel do
    defstruct [:index, :sim, :particles]

    def new(index, width, height) do
      %Panel{
        index: index,
        sim: Sim.new(width, height),
        particles: Particles.new(width, height, 0, 0, [{255, 255, 255}])
      }
    end

    def step(%Panel{} = panel) do
      %Panel{
        panel
        | sim: Sim.step(panel.sim),
          particles: Particles.update(panel.particles, 1 / 30.0)
      }
    end

    def handle_button_press(%Panel{} = panel, color) do
      spawn_pos = {trunc(Installation.panel_width() / 2), -1}

      if Sim.get_cell(panel.sim, spawn_pos) == nil do
        %Panel{panel | sim: Sim.put_cell(panel.sim, spawn_pos, {:sand, color})}
      else
        explode(panel)
      end
    end

    defp explode(%Panel{} = panel) do
      sim = panel.sim
      particles = panel.particles

      particles =
        Enum.reduce(sim.particles, particles, fn {{x, y}, {:sand, color}}, particles ->
          Particles.spawn(particles, {x, y}, 1,
            angle: :math.pi() * 1.5,
            spread: 0.35,
            colors: color,
            min_speed: 30,
            max_speed: 50
          )
        end)

      sim = Sim.clear(sim)

      %Panel{panel | sim: sim, particles: particles}
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

    sim_canvas =
      Enum.map(panels, fn {_, panel} ->
        Sim.draw(panel.sim, Canvas.new(panel.sim.width, panel.sim.height))
      end)
      |> Enum.reduce(&Canvas.join(&2, &1))

    particle_canvas =
      Enum.map(panels, fn {_, panel} ->
        Particles.draw(panel.particles, Canvas.new(panel.particles.width, panel.particles.height))
      end)
      |> Enum.reduce(&Canvas.join(&2, &1))

    canvas =
      Enum.reduce(particle_canvas.pixels, sim_canvas, fn {{x, y}, color}, canvas ->
        Canvas.put_pixel(canvas, {x, y}, color)
      end)

    update_display(canvas)

    {:noreply, %{state | panels: panels}}
  end

  def handle_event(%Input{type: :button, action: :press} = input, state) do
    index = input.button - 1
    color = color_for_panel(index)
    panels = Map.update(state.panels, index, nil, &Panel.handle_button_press(&1, color))
    {:noreply, %{state | panels: panels}}
  end

  def handle_event(_event, state) do
    {:noreply, state}
  end

  defp color_for_panel(index) do
    hue = 360 * index / Installation.num_panels()
    saturation = :rand.uniform() * 25 + 60
    lightness = :rand.uniform() * 25 + 45
    hsl = Chameleon.HSL.new(trunc(hue), trunc(saturation), trunc(lightness))
    %Chameleon.RGB{r: r, g: g, b: b} = Chameleon.convert(hsl, Chameleon.RGB)
    {r, g, b}
  end
end
