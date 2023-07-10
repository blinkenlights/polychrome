# genserver that controlls the game
# uses a timer `:timer.send_interval(interval, self(), :tick) `
# sends current pixels to output
# start game with `Octopus.Apps.Supermario.Game.start_game()`
defmodule Octopus.Apps.Supermario.Game do
  use GenServer
  require Logger

  def start_game() do
    GenServer.start_link(__MODULE__, [interval: 100], name: __MODULE__)
  end

  # states
  #         init           inits the game structure
  #         running        current level is running
  #         levelpause??   between levels
  #         finish         game has finished
  @impl GenServer
  def init(opts) do
    interval = Keyword.fetch!(opts, :interval)
    # init game, all levels, one player, two players, difficulty ??
    #
    state = %{current_level: 0, interval: interval}
    schedule_ticker(state.interval)
    {:ok, state}
  end

  @impl GenServer
  def handle_info(:tick, state) do
    # proceed with level (? every nth tick ?), check wether level has finished or gameover
    # collect points
    # sends current pixels to output?
    schedule_ticker(state.interval)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(:move, state) do
    # handles joystick input
    {:noreply, state}
  end

  def schedule_ticker(interval) do
    :timer.send_interval(interval, self(), :tick)
  end
end
