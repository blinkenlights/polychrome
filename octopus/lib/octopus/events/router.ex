defmodule Octopus.Events.Router do
  @moduledoc """
  Central event router for the Octopus system.

  This module is responsible for routing events to appropriate handlers based on
  event type and system state. It replaces the event handling functionality that
  was previously in the Mixer module.
  """

  use GenServer
  require Logger

  alias Octopus.{AppSupervisor, AppManager, KioskModeManager}
  alias Octopus.Events.Event.Input, as: InputEvent
  alias Octopus.Events.Event.Proximity, as: ProximityEvent
  alias Octopus.Events.Event.Audio, as: AudioEvent
  alias Octopus.Events.Event.Proximity.Processor
  alias Octopus.ButtonServer

  @pubsub_topic "events_router"

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc """
  Route an event to appropriate handlers.

  This is the main entry point for event routing.
  """
  def route_event(event) do
    GenServer.cast(__MODULE__, {:route_event, event})
  end

  @doc """
  Subscribe to events router topics for debugging or monitoring.
  """
  def subscribe do
    Phoenix.PubSub.subscribe(Octopus.PubSub, @pubsub_topic)
  end

  def init(:ok) do
    {:ok, %{}}
  end

  def handle_cast({:route_event, %InputEvent{type: :button} = input_event}, state) do
    ButtonServer.handle_input_event(input_event)
    {:noreply, state}
  end

  def handle_cast({:route_event, %InputEvent{} = input_event}, state) do
    # Route input events to selected app and kiosk mode manager
    selected_app = AppManager.get_selected_app()
    AppSupervisor.send_event(selected_app, input_event)
    GenServer.cast(KioskModeManager, {:input_event, input_event})

    Phoenix.PubSub.broadcast(
      Octopus.PubSub,
      @pubsub_topic,
      {:events_router, {:input_event, input_event}}
    )

    {:noreply, state}
  end

  def handle_cast({:route_event, %AudioEvent{} = audio_event}, state) do
    selected_app = AppManager.get_selected_app()
    AppSupervisor.send_event(selected_app, audio_event)

    Phoenix.PubSub.broadcast(
      Octopus.PubSub,
      @pubsub_topic,
      {:events_router, {:audio_event, audio_event}}
    )

    {:noreply, state}
  end

  def handle_cast({:route_event, %ProximityEvent{} = proximity_event}, state) do
    case Processor.process_event(proximity_event) do
      {:ok, processed_event} ->
        selected_app = AppManager.get_selected_app()
        AppSupervisor.send_event(selected_app, processed_event)

        Phoenix.PubSub.broadcast(
          Octopus.PubSub,
          @pubsub_topic,
          {:events_router, {:proximity_event, processed_event}}
        )

      _ ->
        :noop
    end

    {:noreply, state}
  end

  def handle_cast({:route_event, event}, state) do
    # Log unknown event types for debugging
    Logger.warning("#{__MODULE__}: Unknown event type received: #{inspect(event)}")

    {:noreply, state}
  end
end
