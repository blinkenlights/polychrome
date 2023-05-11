defmodule Octopus.Mixer do
  use GenServer
  require Logger

  alias Octopus.{Broadcaster, Protobuf, AppSupervisor}
  alias Octopus.Protobuf.{Frame, InputEvent}

  defmodule State do
    defstruct selected_app: nil
  end

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def handle_frame(app_id, %Frame{} = frame) when is_binary(app_id) do
    # encode the frame in the app process, so any encoding errors get raised there
    binary = Protobuf.encode(frame)
    GenServer.cast(__MODULE__, {:new_frame, {app_id, binary, frame}})
  end

  def handle_input(%InputEvent{} = input_event) do
    app_id = selected_app()
    AppSupervisor.send_input(app_id, input_event)
  end

  @doc """
  Selects the app with the given `app_id`.
  """
  def select_app(app_id) do
    GenServer.cast(__MODULE__, {:select_app, app_id})
  end

  @spec selected_app :: any
  @doc """
  Returns the currently selected app.
  """
  def selected_app do
    GenServer.call(__MODULE__, :selected_app)
  end

  @doc """
  Subscribes to the mixer topic.

  Published messages:

  * `{:mixer, {:selected_app, app_id}}` - the selected app changed
  * `{:mixer, {:frame, %Octopus.Protobuf.Frame{} = frame}}` - a new frame was received from the selected app
  """
  def subscribe do
    Phoenix.PubSub.subscribe(Octopus.PubSub, "mixer")
  end

  def init(:ok) do
    state = %State{}
    {:ok, state}
  end

  def handle_call(:selected_app, _, %State{selected_app: selected_app} = state) do
    {:reply, selected_app, state}
  end

  def handle_cast({:select_app, app_id}, %State{} = state) do
    Phoenix.PubSub.broadcast(Octopus.PubSub, "mixer", {:mixer, {:selected_app, app_id}})
    {:noreply, %State{state | selected_app: app_id}}
  end

  # no app selected, automatically select the first app that sends a frame
  def handle_cast({:new_frame, {app_id, binary, frame}}, %State{selected_app: nil} = state) do
    Phoenix.PubSub.broadcast(Octopus.PubSub, "mixer", {:mixer, {:frame, frame}})
    Broadcaster.send_binary(binary)
    {:noreply, %State{state | selected_app: app_id}}
  end

  # broadcast frame from selected app
  def handle_cast({:new_frame, {app_id, binary, frame}}, %State{selected_app: app_id} = state) do
    Phoenix.PubSub.broadcast(Octopus.PubSub, "mixer", {:mixer, {:frame, frame}})
    Broadcaster.send_binary(binary)
    {:noreply, state}
  end

  # ignore frames from other apps
  def handle_cast({:new_frame, {_app_id, _binary, _frame}}, state) do
    {:noreply, state}
  end
end
