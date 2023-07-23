defmodule Octopus.Apps.RoundRobinScheduler do
  use Octopus.App
  require Logger

  alias Octopus.Mixer
  alias Octopus.AppSupervisor

  defmodule State do
    defstruct [:selected_app]
  end

  @max_running_time 300_000

  def name(), do: "RoundRobinScheduler"

  def init(_args) do
    AppSupervisor.subscribe()
    Mixer.subscribe()

    Logger.metadata(scheduler: "RoundRobinScheduler")

    selected_app = Mixer.get_selected_app()

    Process.send_after(self(), :next_app, @max_running_time)

    {:ok, %State{selected_app: selected_app}}
  end

  def handle_info(:next_app, %State{} = state) do
    Logger.debug("next_app")
    state = select_next_app(state)
    Process.send_after(self(), :next_app, @max_running_time)
    {:noreply, state}
  end

  def handle_info({:apps, {:stopped, app_id}}, %State{selected_app: app_id} = state) do
    Logger.info("meh")
    state = %State{state | selected_app: nil} |> select_next_app() |> IO.inspect()
    {:noreply, state}
  end

  def handle_info({:apps, msg}, %State{} = state) do
    Logger.info({msg, state} |> inspect())
    {:noreply, state}
  end

  def handle_info({:mixer, {:selected_app, app_id}}, %State{} = state) do
    {:noreply, %State{state | selected_app: app_id}}
  end

  def handle_info({:mixer, _}, %State{} = state) do
    {:noreply, state}
  end

  defp select_next_app(%State{selected_app: nil} = state) do
    case get_running_apps() do
      [] ->
        Logger.info("No apps to select from")
        state

      [head | _tail] ->
        Mixer.select_app(head)
        %State{state | selected_app: head}
    end
  end

  defp select_next_app(%State{} = state) do
    Logger.info("Selecting next app")

    case get_running_apps() do
      [] ->
        Logger.info("No apps to select from")
        state

      [app_id] ->
        Mixer.select_app(app_id)
        %State{state | selected_app: app_id}
        state

      apps ->
        next_app_id =
          (apps ++ apps)
          |> Enum.drop_while(fn app_id -> app_id != state.selected_app end)
          |> Enum.at(1)

        Logger.debug("Selecting #{next_app_id}")

        Mixer.select_app(next_app_id)

        %State{state | selected_app: next_app_id}
    end
  end

  defp get_running_apps do
    AppSupervisor.running_apps()
    |> Enum.map(fn {_module, app_id} -> app_id end)
    |> Enum.reject(fn app_id -> app_id == AppSupervisor.lookup_app_id(self()) end)
    |> Enum.sort_by(fn app_id -> app_id end)
  end
end
