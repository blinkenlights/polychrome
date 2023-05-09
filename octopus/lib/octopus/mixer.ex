defmodule Octopus.Mixer do
  use GenServer
  require Logger

  alias Octopus.{AppSupervisor, Broadcaster, Protobuf}
  alias Octopus.Protobuf.{Config, Frame}

  defmodule State do
    defstruct selected_app: nil
  end

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def handle_frame(app_id, %Frame{} = frame) when is_binary(app_id) do
    # we encode the frame in the app process, so any encoding errors get raised there
    binary = Protobuf.encode(frame)
    GenServer.cast(__MODULE__, {:new_frame, {app_id, binary}})
  end

  def init(:ok) do
    state = %State{}

    {:ok, state}
  end

  # no app selected, automatically select the first app that sends a frame
  def handle_cast({:new_frame, {app_id, frame}}, %State{selected_app: nil} = state) do
    Broadcaster.send_binary(frame)
    {:noreply, %State{state | selected_app: app_id}}
  end

  # broadcast frame from selected app
  def handle_cast({:new_frame, {app_id, frame}}, %State{selected_app: app_id} = state) do
    Broadcaster.send_binary(frame)
    {:noreply, state}
  end

  # ignore frames from other apps
  def handle_cast({:new_frame, {_app_id, _frame}}, state) do
    {:noreply, state}
  end
end
