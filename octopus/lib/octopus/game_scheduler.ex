defmodule Octopus.GameScheduler do
  use GenServer
  require Logger

  alias Octopus.{AppSupervisor, Mixer, Repo}

  @left_app Octopus.Apps.Snake
  @right_app Octopus.Apps.Supermario

  defmodule State do
    defstruct []
  end

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def start() do
    GenServer.cast(__MODULE__, :start)
  end

  def init(:ok) do
    {:ok, %State{}}
  end

  def handle_cast(:start, %State{} = state) do
    {:ok, left_pid} = AppSupervisor.start_app(@left_app)
    {:ok, right_pid} = AppSupervisor.start_app(@right_app)

    Mixer.select_app(
      {AppSupervisor.lookup_app_id(left_pid), AppSupervisor.lookup_app_id(right_pid)}
    )

    {:noreply, state}
  end
end
