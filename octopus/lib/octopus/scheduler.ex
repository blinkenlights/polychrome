defmodule Octopus.Scheduler do
  use GenServer
  require Logger

  alias Octopus.{AppSupervisor, Mixer}

  @schedule [
    %{module: Octopus.Apps.Text, config: %{text: "POLYCHROME"}, timeout: 10_000},
    %{module: Octopus.Apps.Text, config: %{text: "MILDENBERG"}, timeout: 10_000},
    %{module: Octopus.Apps.Text, config: %{text: "WILLKOMMEN"}, timeout: 10_000},
    %{module: Octopus.Apps.Text, config: %{text: "EXPERIENCE"}, timeout: 10_000}
  ]
  @topic "scheduler"

  defmodule State do
    defstruct [:schedule, :current_app]
  end

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def subscribe() do
    Phoenix.PubSub.subscribe(Octopus.PubSub, @topic)
    broadcast_status()
  end

  def start() do
    GenServer.cast(__MODULE__, :start)
  end

  def stop() do
    GenServer.cast(__MODULE__, :stop)
  end

  def broadcast_status() do
    GenServer.cast(__MODULE__, :broadcast_status)
  end

  def init(:ok) do
    {:ok, %State{schedule: @schedule}}
  end

  def handle_cast(:start, %State{current_app: nil} = state) do
    Logger.info("Starting schedule")
    send(self(), :next)
    {:noreply, %State{state | schedule: @schedule}}
  end

  def handle_cast(:start, %State{} = state) do
    Logger.info("Schedule already started")
    {:noreply, state}
  end

  def handle_cast(:stop, %State{} = state) do
    Logger.info("Stopping schedule")

    if state.current_app != nil do
      AppSupervisor.stop_app(state.current_app)
    end

    {:noreply, %State{state | schedule: [], current_app: nil} |> broadcast()}
  end

  def handle_cast(:broadcast_status, %State{} = state) do
    broadcast(state)
    {:noreply, state}
  end

  def handle_info(:next, %State{schedule: []} = state) do
    Logger.info("Schedule finished, restarting")
    send(self(), :next)
    {:noreply, %State{state | schedule: @schedule}}
  end

  def handle_info(:next, %State{schedule: [next | rest]} = state) do
    Logger.info(
      "Scheduling next app #{inspect(next.module)} with config #{inspect(next.config)}. Timeout: #{inspect(next.timeout)}"
    )

    if state.current_app != nil do
      AppSupervisor.stop_app(state.current_app)
    end

    {:ok, pid} = AppSupervisor.start_app(next.module, config: next.config)
    app_id = AppSupervisor.lookup_app_id(pid)
    Mixer.select_app(app_id)

    :timer.send_after(next.timeout, self(), :next)

    {:noreply, %State{state | schedule: rest, current_app: app_id} |> broadcast()}
  end

  defp broadcast(%State{} = state) do
    msg =
      case state.current_app do
        nil -> {:scheduler, :stopped}
        app_id -> {:scheduler, {:running, app_id}}
      end

    Phoenix.PubSub.broadcast(Octopus.PubSub, @topic, msg)
    state
  end
end
