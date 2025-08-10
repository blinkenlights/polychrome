defmodule Octopus.SpaceMouse.Simulator do
  @moduledoc """
  SpaceMouse event simulator for testing without physical hardware.
  
  This module can generate fake SpaceMouse events to test the integration
  when no physical SpaceMouse device is available.
  """
  
  use GenServer
  require Logger
  
  alias Octopus.Events.Event.SpaceMouse, as: SpaceMouseEvent
  alias Octopus.Events.Router
  
  defmodule State do
    @moduledoc false
    defstruct [:timer_ref, :running]
  end
  
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end
  
  @doc """
  Starts generating fake SpaceMouse events.
  """
  def start_simulation do
    GenServer.cast(__MODULE__, :start_simulation)
  end
  
  @doc """
  Stops generating fake SpaceMouse events.
  """
  def stop_simulation do
    GenServer.cast(__MODULE__, :stop_simulation)
  end
  
  @doc """
  Sends a single fake motion event.
  """
  def send_fake_motion(x \\ nil, y \\ nil, z \\ nil, rx \\ nil, ry \\ nil, rz \\ nil) do
    motion = %{
      x: x || :rand.uniform() * 2 - 1,    # -1.0 to 1.0
      y: y || :rand.uniform() * 2 - 1,
      z: z || :rand.uniform() * 2 - 1,
      rx: rx || :rand.uniform() * 2 - 1,
      ry: ry || :rand.uniform() * 2 - 1,
      rz: rz || :rand.uniform() * 2 - 1
    }
    
    event = SpaceMouseEvent.motion(motion.x, motion.y, motion.z, motion.rx, motion.ry, motion.rz)
    Logger.info("SpaceMouse Simulator: Sending fake motion: #{inspect(motion)}")
    Router.route_event(event)
  end
  
  @doc """
  Sends a fake button event.
  """
  def send_fake_button(id \\ 1, state \\ :pressed) do
    event = SpaceMouseEvent.button(id, state)
    Logger.info("SpaceMouse Simulator: Sending fake button: #{id} #{state}")
    Router.route_event(event)
  end
  
  @doc """
  Sends a fake connection event.
  """
  def send_fake_connection do
    event = SpaceMouseEvent.connected(0x256F, 0xC635, "Simulated SpaceMouse")
    Logger.info("SpaceMouse Simulator: Sending fake connection")
    Router.route_event(event)
  end
  
  @impl true
  def init(:ok) do
    {:ok, %State{timer_ref: nil, running: false}}
  end
  
  @impl true
  def handle_cast(:start_simulation, state) do
    if state.running do
      {:noreply, state}
    else
      Logger.info("SpaceMouse Simulator: Starting continuous simulation")
      
      # Send initial connection event
      send_fake_connection()
      
      # Start timer for continuous motion events
      timer_ref = :timer.send_interval(100, self(), :generate_motion) # 10 Hz
      
      new_state = %State{state | timer_ref: timer_ref, running: true}
      {:noreply, new_state}
    end
  end
  
  def handle_cast(:stop_simulation, state) do
    if state.timer_ref do
      :timer.cancel(state.timer_ref)
      Logger.info("SpaceMouse Simulator: Stopping simulation")
    end
    
    new_state = %State{state | timer_ref: nil, running: false}
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info(:generate_motion, state) do
    # Generate smooth motion using sine waves for more realistic movement
    time = System.monotonic_time(:millisecond) / 1000.0
    
    motion = %{
      x: 0.3 * :math.sin(time * 0.5),
      y: 0.2 * :math.cos(time * 0.7),
      z: 0.1 * :math.sin(time * 0.3),
      rx: 0.15 * :math.cos(time * 0.8),
      ry: 0.25 * :math.sin(time * 0.4),
      rz: 0.1 * :math.cos(time * 0.6)
    }
    
    event = SpaceMouseEvent.motion(motion.x, motion.y, motion.z, motion.rx, motion.ry, motion.rz)
    Router.route_event(event)
    
    {:noreply, state}
  end
  
  def handle_info(msg, state) do
    Logger.debug("SpaceMouse Simulator: Unhandled message: #{inspect(msg)}")
    {:noreply, state}
  end
end
