defmodule Octopus.ButtonServer do
  use GenServer

  alias Octopus.Events.Router
  alias Octopus.InputAdapter
  alias Octopus.AppManager
  alias Octopus.Events.Event.Input
  alias Octopus.Installation
  alias Octopus.AppSupervisor

  require Logger

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    Router.subscribe()
    AppManager.subscribe()
    AppSupervisor.subscribe()

    {:ok, %{selected_app: nil, subscribed_apps: MapSet.new()}}
  end

  def handle_info({:apps, {:stopped, app_id}}, %{selected_app: app_id} = state) do
    turn_off_all_buttons()
    {:noreply, unsubscribe_app(state, app_id)}
  end

  def handle_info({:apps, {:stopped, app_id}}, state) do
    {:noreply, unsubscribe_app(state, app_id)}
  end

  def handle_info({:app_manager, {:selected_app, selected_app}}, state) do
    state = %{state | selected_app: selected_app}

    if MapSet.member?(state.subscribed_apps, selected_app) do
      turn_on_all_buttons()
    end

    {:noreply, state}
  end

  def handle_info(message, state) do
    Logger.debug("unhandled message, #{inspect(message)}")
    {:noreply, state}
  end

  def subscribe(app_id) do
    GenServer.cast(__MODULE__, {:subscribe, app_id})
  end

  def handle_input_event(%Input{type: :button} = input) do
    dbg("handling input event")
    dbg(input)
    GenServer.cast(__MODULE__, {:input_event, input})
  end

  def handle_cast({:subscribe, app_id}, %{selected_app: app_id} = state) do
    turn_on_all_buttons()
    {:noreply, subscribe_app(state, app_id)}
  end

  def handle_cast({:subscribe, app_id}, state) do
    {:noreply, subscribe_app(state, app_id)}
  end

  def handle_cast({:input_event, %Input{type: :button} = input}, state) do
    if MapSet.member?(state.subscribed_apps, state.selected_app) do
      dbg("sending event to #{state.selected_app}")

      case Octopus.AppSupervisor.lookup_app(state.selected_app) do
        {pid, _} -> send(pid, {:event, input})
        nil -> Logger.warning("App #{state.selected_app} not found")
      end
    end

    {:noreply, state}
  end

  defp unsubscribe_app(state, app_id) do
    %{state | subscribed_apps: MapSet.delete(state.subscribed_apps, app_id)}
  end

  defp subscribe_app(state, app_id) do
    %{state | subscribed_apps: MapSet.put(state.subscribed_apps, app_id)}
  end

  defp turn_on_all_buttons() do
    for button <- 1..Installation.num_buttons() do
      InputAdapter.send_light_event(button, 1_000_000)
    end
  end

  defp turn_off_all_buttons() do
    for button <- 1..Installation.num_buttons() do
      InputAdapter.send_light_event(button, 0)
    end
  end
end
