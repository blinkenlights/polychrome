defmodule Octopus.Apps.Fireworks do
  use Octopus.App, category: :game
  use Octopus.Params, prefix: :shapes

  alias Octopus.Installation
  alias Octopus.Events.Event.Input
  alias Octopus.Canvas
  alias Octopus.Apps.Shapes.Panel
  alias Octopus.Apps.Shapes.State

  def name, do: "Fireworks"

  def compatible?() do
    Installation.panel_width() == 8 &&
      Installation.panel_height() == 8 &&
      Installation.num_buttons() == Installation.num_panels()
  end

  defmodule Particle do
    defstruct [:color, :x, :y, :vx, :vy, :ttl]
  end

  defmodule Panel do
    defstruct [
      :index,
      :width,
      :height,
      :particles,
      :num_panels
    ]

    def new(index, width, height, num_panels) do
      %__MODULE__{
        index: index,
        width: width,
        height: height,
        particles: [],
        num_panels: num_panels
      }
    end

    def update(%__MODULE__{} = panel, dt) do
      panel
      |> update_particles(dt)
    end

    defp vector_from_angle(angle) do
      x = :math.cos(angle)
      y = :math.sin(angle)
      {x, y}
    end

    def spawn_particles(%__MODULE__{} = panel, {x, y}, angle, num_particles) do
      colors =
        Stream.repeatedly(fn ->
          hue = 360 * panel.index / panel.num_panels
          saturation = :rand.uniform() * 25 + 60
          lightness = :rand.uniform() * 25 + 45
          hsl = Chameleon.HSL.new(trunc(hue), trunc(saturation), trunc(lightness))
          %Chameleon.RGB{r: r, g: g, b: b} = Chameleon.convert(hsl, Chameleon.RGB)
          {r, g, b}
        end)

      new_particles =
        colors
        |> Stream.cycle()
        |> Enum.take(num_particles)
        |> Enum.map(fn color ->
          variance = (:rand.uniform() - 0.5) * 0.5
          angle = angle + variance
          {vx, vy} = vector_from_angle(angle)
          speed = :rand.uniform() * 25 + 25

          %Particle{
            color: color,
            x: x,
            y: y,
            vx: vx * speed,
            vy: vy * speed,
            ttl: :rand.uniform() * 2 + 0.5
          }
        end)

      %__MODULE__{panel | particles: panel.particles ++ new_particles}
    end

    def draw(%__MODULE__{} = panel) do
      draw_particles(panel)
      |> Canvas.cut({0, 0}, {7, 7})
    end

    defp update_particles(%__MODULE__{} = panel, dt) do
      particles =
        panel.particles
        |> Enum.map(fn particle ->
          vy = particle.vy + 90.81 * dt
          vx = particle.vx

          %Particle{
            particle
            | vx: vx,
              vy: vy,
              x: particle.x + vx * dt,
              y: particle.y + vy * dt,
              ttl: particle.ttl - dt
          }
        end)
        |> Enum.filter(fn particle -> particle.ttl > 0 end)

      %__MODULE__{panel | particles: particles}
    end

    defp draw_particles(%__MODULE__{} = panel) do
      particles =
        panel.particles
        |> Enum.filter(fn particle ->
          particle.x >= 0 and particle.y >= 0 and particle.x < panel.width and
            particle.y < panel.height
        end)

      Enum.reduce(particles, Canvas.new(panel.width, panel.height), fn particle, canvas ->
        color =
          if particle.ttl < 1 do
            {r, g, b} = particle.color
            {trunc(r * particle.ttl), trunc(g * particle.ttl), trunc(b * particle.ttl)}
          else
            particle.color
          end

        Canvas.put_pixel(canvas, {round(particle.x), round(particle.y)}, color)
      end)
    end
  end

  defmodule State do
    defstruct [
      :panels
    ]
  end

  @fps 60
  @frame_time_ms trunc(1000 / @fps)
  @frame_time_s 1.0 / @fps

  def app_init(_args) do
    Octopus.App.configure_display(layout: :adjacent_panels)

    panels =
      Map.new(0..(Installation.num_panels() - 1), fn i ->
        panel =
          Panel.new(
            i,
            Installation.panel_width(),
            Installation.panel_height(),
            Installation.num_panels()
          )

        {i, panel}
      end)

    state = %State{
      panels: panels
    }

    :timer.send_interval(@frame_time_ms, :tick)
    send(self(), :tick)

    {:ok, state}
  end

  def handle_event(
        %Input{type: :button, action: :press, button: button_number},
        %State{} = state
      ) do
    index = button_number - 1

    panels =
      state.panels
      |> Map.get(index)
      |> Panel.spawn_particles(
        {Installation.panel_width() / 2, Installation.panel_height()},
        :math.pi() * 3 / 2,
        15
      )
      |> then(&Map.put(state.panels, index, &1))

    state = %{state | panels: panels}

    {:noreply, state}
  end

  def handle_event(_event, state) do
    {:noreply, state}
  end

  def handle_info(:tick, %State{} = state) do
    state.panels
    |> Map.values()
    |> Enum.map(&Panel.draw/1)
    |> Enum.reduce(&Canvas.join(&2, &1))
    |> update_display()

    panels =
      state.panels
      |> Enum.map(fn {id, panel} -> {id, Panel.update(panel, @frame_time_s)} end)
      |> Map.new()

    state = %State{state | panels: panels}

    {:noreply, state}
  end
end
