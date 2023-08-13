defmodule Octopus.Scheduler do
  use GenServer
  require Logger

  alias Octopus.{AppSupervisor, Mixer}

  @schedule [
    %{module: Octopus.Apps.Text, config: %{text: "POLYCHROME"}, timeout: 90_000},
    %{module: Octopus.Apps.Text, config: %{text: "MILDENBERG"}, timeout: 90_000},
    %{module: Octopus.Apps.Text, config: %{text: "WILLKOMMEN"}, timeout: 90_000},
    %{module: Octopus.Apps.Text, config: %{text: "EXPERIENCE"}, timeout: 10_000}
  ]

  defmodule State do
    defstruct [:schedule, :current_app]
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
    {:ok, %State{schedule: @schedule}}
  end

  def handle_cast(:start, %State{} = state) do
    Logger.info("Starting schedule")
    send(self(), :next)
    {:noreply, %State{state | schedule: @schedule}}
  end

  def handle_cast(:stop, %State{} = state) do
    Logger.info("Stopping schedule")
    {:noreply, %State{state | schedule: []}}
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

    {:noreply, %State{state | schedule: rest, current_app: app_id}}
  end
end