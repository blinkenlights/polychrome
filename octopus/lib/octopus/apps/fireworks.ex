defmodule Octopus.Apps.Fireworks do
  use Octopus.App, category: :game
  use Octopus.Params, prefix: :shapes

  alias Octopus.Installation
  alias Octopus.Events.Event.Input
  alias Octopus.Canvas
  alias Octopus.Apps.Shapes.State
  alias Octopus.Particles

  def name, do: "Fireworks"

  def compatible?() do
    Installation.panel_width() == 8 &&
      Installation.panel_height() == 8 &&
      Installation.num_buttons() == Installation.num_panels()
  end

  defmodule Particle do
    defstruct [:color, :x, :y, :vx, :vy, :ttl]
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
        colors =
          Stream.repeatedly(fn ->
            hue = 360 * i / Installation.num_panels()
            saturation = :rand.uniform() * 25 + 60
            lightness = :rand.uniform() * 25 + 45
            hsl = Chameleon.HSL.new(trunc(hue), trunc(saturation), trunc(lightness))
            %Chameleon.RGB{r: r, g: g, b: b} = Chameleon.convert(hsl, Chameleon.RGB)
            {r, g, b}
          end)

        panel =
          Particles.new(
            Installation.panel_width(),
            Installation.panel_height(),
            :math.pi() * 3.5,
            0.05,
            colors
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
      |> Particles.spawn({Installation.panel_width() / 2, Installation.panel_height()}, 25)
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
    |> Enum.map(
      &Particles.draw(&1, Canvas.new(Installation.panel_width(), Installation.panel_height()))
    )
    |> Enum.reduce(&Canvas.join(&2, &1))
    |> update_display()

    panels =
      state.panels
      |> Enum.map(fn {id, panel} -> {id, Particles.update(panel, @frame_time_s)} end)
      |> Map.new()

    state = %State{state | panels: panels}

    {:noreply, state}
  end
end
