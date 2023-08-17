defmodule Octopus.GameScheduler do
  use GenServer
  require Logger

  alias Jason.Encoder.Octopus.PlaylistScheduler
  alias Octopus.{AppSupervisor, Mixer, Rep, PlaylistScheduler}

  @games [Octopus.Apps.Snake, Octopus.Apps.Supermario]

  defmodule State do
    defstruct app_ids: %{}, status: :stopped
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

  def init(:ok) do
    {:ok, %State{}}
  end

  def handle_cast(:start, %State{status: :stopped} = state) do
    state =
      %State{state | status: :running}
      |> start_game(:left, Enum.at(@games, 0))
      |> start_game(:right, Enum.at(@games, 1))

    {:noreply, state}
  end

  def handle_cast(:start, state), do: {:noreply, state}

  def handle_cast(:stop, %State{} = state) do
    AppSupervisor.stop_app(Map.get(state.app_ids, :left))
    AppSupervisor.stop_app(Map.get(state.app_ids, :right))

    {:noreply, %State{state | status: :stopped, app_ids: %{}}}
  end

  def start_game(%State{} = state, side, module) when side in [:left, :right] do
    {:ok, pid} = AppSupervisor.start_app(module, config: %{side: side})
    app_id = AppSupervisor.lookup_app_id(pid)
    Mixer.select_app(app_id, side)

    %State{app_ids: Map.put(state.app_ids, side, app_id)}
  end
end
