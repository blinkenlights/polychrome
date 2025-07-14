defmodule Octopus.Apps.Sand do
  use Octopus.App, category: :game

  alias Octopus.Installation
  alias Octopus.Canvas
  alias Octopus.Apps.Sand.Sim

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

    :timer.send_interval(trunc(1000 / 30), self(), :tick)
    send(self(), :tick)

    {:ok, %{sims: sims}}
  end

  def handle_info(:tick, state) do
    sims = Enum.map(state.sims, &Sim.step(&1, 1 / 30.0))

    canvas =
      sims
      |> Enum.map(&Sim.draw(&1, Canvas.new(&1.width, &1.height)))
      |> Enum.reduce(&Canvas.join(&2, &1))

    update_display(canvas)

    {:noreply, %{state | sims: sims}}
  end
end
