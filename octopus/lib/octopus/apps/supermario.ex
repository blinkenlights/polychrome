defmodule Octopus.Apps.Supermario do
  use Octopus.App
  require Logger

  alias Octopus.Apps.Supermario.PngFile
  # alias Octopus.{ColorPalette, Canvas}
  # alias Octopus.Protobuf.InputEvent

  defmodule State do
    defstruct [:game, :canvas, :interval]
  end

  def name(), do: "Supermario"

  def init(_args) do
    canvas = PngFile.init_canvas_for_level(1)

    state = %State{
      interval: 100,
      canvas: canvas
    }

    # init game, all levels, one player, two players, difficulty ??

    # states
    #         init           inits the game structure
    #         running        current level is running
    #         levelpause??   between levels
    #         finish         game has finished
    schedule_ticker(state.interval)
    {:ok, state}
  end

  def handle_info(:tick, state) do
    # proceed with level (? every nth tick ?), check wether level has finished or gameover
    # collect points
    # sends current pixels to output?
    schedule_ticker(state.interval)
    {:noreply, state}
  end

  def handle_info(:move, state) do
    # handles joystick input
    {:noreply, state}
  end

  def schedule_ticker(interval) do
    :timer.send_interval(interval, self(), :tick)
  end
end
