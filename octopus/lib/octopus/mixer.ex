defmodule Octopus.Mixer do
  use GenServer
  require Logger

  alias Octopus.{Broadcaster, Protobuf, AppSupervisor}
  alias Octopus.Protobuf.{Frame, WFrame, RGBFrame, AudioFrame, InputEvent}

  @pubsub_topic "mixer"
  @supported_frames [Frame, WFrame, RGBFrame, AudioFrame]
  @transition_duration 300
  @transition_frame_time trunc(1000 / 60)

  defmodule State do
    defstruct selected_app: nil,
              last_selected_app: nil,
              rendered_app: nil,
              transition: nil,
              max_luminance: 255
  end

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def handle_frame(app_id, %RGBFrame{} = frame) do
    # Split RGB frames to avoid UPD fragmenting. Can be removed when we fix the fragmenting in the firmware
    Protobuf.split_and_encode(frame)
    |> Enum.each(fn binary ->
      send_frame(binary, frame, app_id)
    end)
  end

  def handle_frame(app_id, %frame_type{} = frame) when frame_type in @supported_frames do
    # encode the frame in the app process, so any encoding errors get raised there
    Protobuf.encode(frame)
    |> send_frame(frame, app_id)
  end

  defp send_frame(binary, frame, app_id) do
    GenServer.cast(__MODULE__, {:new_frame, {app_id, binary, frame}})
  end

  def handle_input(%InputEvent{} = input_event) do
    app_id = get_selected_app()
    AppSupervisor.send_input(app_id, input_event)
  end

  @doc """
  Selects the app with the given `app_id`.
  """
  def select_app(app_id) do
    GenServer.cast(__MODULE__, {:select_app, app_id})
  end

  @doc """
  Returns the currently selected app.
  """
  def get_selected_app() do
    GenServer.call(__MODULE__, :get_selected_app)
  end

  @doc """
  Subscribes to the mixer topic.

  Published messages:

  * `{:mixer, {:selected_app, app_id}}` - the selected app changed
  * `{:mixer, {:frame, %Octopus.Protobuf.Frame{} = frame}}` - a new frame was received from the selected app
  """
  def subscribe do
    Phoenix.PubSub.subscribe(Octopus.PubSub, @pubsub_topic)
  end

  def init(:ok) do
    state = %State{}
    {:ok, state}
  end

  def handle_call(:get_selected_app, _, %State{selected_app: selected_app} = state) do
    {:reply, selected_app, state}
  end

  # broadcast frames from rendered app
  def handle_cast({:new_frame, {app_id, binary, frame}}, %State{rendered_app: app_id} = state) do
    send_frame(binary, frame)
    {:noreply, state}
  end

  # ignore frames from other apps
  def handle_cast({:new_frame, {_app_id, _binary, _frame}}, state) do
    {:noreply, state}
  end

  ### App Transitions ###
  # Implemented with a simple state machine that is represented by the `transition` field in the state.
  # Possible values are `{:in, time_left}`, `{:out, time_left}` and `nil`.

  def handle_cast({:select_app, next_app_id}, %State{transition: nil} = state) do
    state =
      %State{
        state
        | transition: {:out, @transition_duration},
          selected_app: next_app_id,
          last_selected_app: state.selected_app
      }

    broadcast_selected_app(state)
    schedule_transition()

    {:noreply, state}
  end

  def handle_cast({:select_app, next_app_id}, %State{transition: {:out, _}} = state) do
    state = %State{
      state
      | selected_app: next_app_id
    }

    broadcast_selected_app(state)

    {:noreply, state}
  end

  def handle_cast({:select_app, next_app_id}, %State{transition: {:in, time_left}} = state) do
    state = %State{
      state
      | transition: {:out, @transition_duration - time_left},
        selected_app: next_app_id,
        last_selected_app: state.selected_app
    }

    {:noreply, state}
  end

  def handle_info(:transition, %State{transition: nil} = state) do
    {:noreply, state}
  end

  def handle_info(:transition, %State{transition: {:out, time}} = state) when time <= 0 do
    state = %State{state | transition: {:in, @transition_duration}}
    Broadcaster.set_luminance(0)

    schedule_transition()

    {:noreply, state}
  end

  def handle_info(:transition, %State{transition: {:out, time}} = state) do
    state = %State{
      state
      | transition: {:out, time - @transition_frame_time},
        rendered_app: state.last_selected_app
    }

    (Easing.cubic_in(time / @transition_duration) * state.max_luminance)
    |> round()
    |> Broadcaster.set_luminance()

    schedule_transition()

    {:noreply, state}
  end

  def handle_info(:transition, %State{transition: {:in, time}} = state) when time <= 0 do
    state = %State{state | transition: nil}
    Broadcaster.set_luminance(state.max_luminance)

    {:noreply, state}
  end

  def handle_info(:transition, %State{transition: {:in, time}} = state) do
    state = %State{
      state
      | transition: {:in, time - @transition_frame_time},
        rendered_app: state.selected_app
    }

    ((1 - Easing.cubic_out(time / @transition_duration)) * state.max_luminance)
    |> round()
    |> Broadcaster.set_luminance()

    schedule_transition()

    {:noreply, state}
  end

  ### End App Transitions ###

  defp send_frame(binary, %frame_type{} = frame) when frame_type in @supported_frames do
    Phoenix.PubSub.broadcast(Octopus.PubSub, @pubsub_topic, {:mixer, {:frame, frame}})
    Broadcaster.send_binary(binary)
  end

  defp schedule_transition() do
    Process.send_after(self(), :transition, @transition_frame_time)
  end

  defp broadcast_selected_app(%State{selected_app: selected_app}) do
    Phoenix.PubSub.broadcast(
      Octopus.PubSub,
      @pubsub_topic,
      {:mixer, {:selected_app, selected_app}}
    )
  end
end
