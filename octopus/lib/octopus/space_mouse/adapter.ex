defmodule Octopus.SpaceMouse.Adapter do
  @moduledoc """
  Adapter for translating SpaceMouse library events into Octopus events.

  This module acts as a bridge between the external SpaceMouse library
  and the Octopus event system, converting raw SpaceMouse events into
  proper Octopus.Events.Event.SpaceMouse structs and routing them
  through the events system.
  """

  use GenServer
  require Logger

  alias Octopus.Events.Event.SpaceMouse, as: SpaceMouseEvent
  alias Octopus.Events.Router

  @topic "spacemouse_adapter"

  defmodule State do
    @moduledoc false
    defstruct [:subscribed, :led_state]
  end

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc """
  Subscribe to SpaceMouse adapter events for debugging or monitoring.
  """
  def subscribe do
    Phoenix.PubSub.subscribe(Octopus.PubSub, @topic)
  end

  @impl true
  def init(:ok) do
    # Subscribe to SpaceMouse library events
    :ok = SpaceMouse.subscribe()

    {:ok, %State{subscribed: true, led_state: :unknown}}
  end

  @impl true
  def handle_info({:spacemouse_connected, device_info}, state) do
    Logger.info("SpaceMouse connected: #{inspect(device_info)}")

    # Extract device information
    vendor_id = Map.get(device_info, :vendor_id, 0)
    product_id = Map.get(device_info, :product_id, 0)
    name = Map.get(device_info, :name, "Unknown SpaceMouse")

    event = SpaceMouseEvent.connected(vendor_id, product_id, name)

    Router.route_event(event)

    Phoenix.PubSub.broadcast(
      Octopus.PubSub,
      @topic,
      {:spacemouse_adapter, {:connected, device_info}}
    )

    {:noreply, state}
  end

  def handle_info({:spacemouse_disconnected, device_info}, state) do
    Logger.info("SpaceMouse disconnected: #{inspect(device_info)}")

    # Extract device information
    vendor_id = Map.get(device_info, :vendor_id, 0)
    product_id = Map.get(device_info, :product_id, 0)
    name = Map.get(device_info, :name, "Unknown SpaceMouse")

    event = SpaceMouseEvent.disconnected(vendor_id, product_id, name)

    Router.route_event(event)

    Phoenix.PubSub.broadcast(
      Octopus.PubSub,
      @topic,
      {:spacemouse_adapter, {:disconnected, device_info}}
    )

    {:noreply, state}
  end

  def handle_info({:spacemouse_motion, motion_data}, state) do
    # Debug logging - check if we're getting real values
    # Extract motion values
    %{x: x, y: y, z: z, rx: rx, ry: ry, rz: rz} = motion_data

    event = SpaceMouseEvent.motion(x, y, z, rx, ry, rz)

    Router.route_event(event)

    Phoenix.PubSub.broadcast(
      Octopus.PubSub,
      @topic,
      {:spacemouse_adapter, {:motion, motion_data}}
    )

    {:noreply, state}
  end

  def handle_info({:spacemouse_button, button_data}, state) do
    # Convert button data to SpaceMouse event
    %{id: id, state: button_state} = button_data

    event = SpaceMouseEvent.button(id, button_state)

    Router.route_event(event)

    Phoenix.PubSub.broadcast(
      Octopus.PubSub,
      @topic,
      {:spacemouse_adapter, {:button, button_data}}
    )

    {:noreply, state}
  end

  def handle_info({:spacemouse_led, led_data}, state) do
    # Convert LED data to SpaceMouse event
    %{from: from, to: to, timestamp: timestamp} = led_data

    event = SpaceMouseEvent.led(from, to, timestamp)

    Router.route_event(event)

    Phoenix.PubSub.broadcast(
      Octopus.PubSub,
      @topic,
      {:spacemouse_adapter, {:led, led_data}}
    )

    new_state = %State{state | led_state: to}
    {:noreply, new_state}
  end

  def handle_info(message, state) do
    Logger.debug("#{__MODULE__}: Unhandled message: #{inspect(message)}")
    {:noreply, state}
  end

  @impl true
  def handle_call(:get_led_state, _from, state) do
    {:reply, state.led_state, state}
  end

  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @doc """
  Gets the current LED state as tracked by the adapter.
  """
  def get_led_state do
    GenServer.call(__MODULE__, :get_led_state)
  end

  @doc """
  Gets the current adapter state for debugging.
  """
  def get_state do
    GenServer.call(__MODULE__, :get_state)
  end
end
