defmodule Octopus.GameScheduler do
  use GenServer
  require Logger

  alias Octopus.{AppSupervisor, Mixer, Rep}

  @games [Octopus.Apps.Snake, Octopus.Apps.Supermario]

  defmodule State do
    defstruct app_ids: %{}, app_indices: %{left: 0, right: 1}, status: :stopped
  end

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def start() do
    GenServer.cast(__MODULE__, :start)
  end

  def stop() do
    GenServer.cast(__MODULE__, :stop)
  end

  def next_game(side) when side in [:left, :right] do
    GenServer.cast(__MODULE__, {:next_game, side})
  end

  def init(:ok) do
    {:ok, %State{}}
  end

  def handle_cast(:start, %State{status: :stopped} = state) do
    state =
      %State{state | status: :running}
      |> start_game(:left)
      |> start_game(:right)

    {:noreply, state}
  end

  def handle_cast(:start, state), do: {:noreply, state}

  def handle_cast(:stop, %State{} = state) do
    AppSupervisor.stop_app(Map.get(state.app_ids, :left))
    AppSupervisor.stop_app(Map.get(state.app_ids, :right))

    {:noreply, %State{state | status: :stopped, app_ids: %{}}}
  end

  def handle_cast({:next_game, side}, %State{status: :running} = state) do
    index = rem(state.app_indices[side] + 1, length(@games))

    state =
      %{state | app_indices: Map.put(state.app_indices, side, index)}
      |> start_game(side)

    {:noreply, state}
  end

  def handle_cast({:next_game, _}, %State{status: :stopped} = state) do
    {:noreply, state}
  end

  def start_game(%State{} = state, side) when side in [:left, :right] do
    module = Enum.at(@games, Map.get(state.app_indices, side, nil))
    AppSupervisor.stop_app(Map.get(state.app_ids, side))

    {:ok, pid} = AppSupervisor.start_app(module, config: %{side: side})
    app_id = AppSupervisor.lookup_app_id(pid)
    Mixer.select_app(app_id, side)

    %State{state | app_ids: Map.put(state.app_ids, side, app_id)}
  end
end
