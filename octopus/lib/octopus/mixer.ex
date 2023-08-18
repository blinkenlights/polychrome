defmodule Octopus.Mixer do
  use GenServer
  require Logger

  alias Octopus.Protobuf.SoundToLightControlEvent
  alias Octopus.Protobuf.AudioFrame
  alias Octopus.GameScheduler
  alias Octopus.{Broadcaster, Protobuf, AppSupervisor, PlaylistScheduler, Canvas, GameScheduler}

  alias Octopus.Protobuf.{
    Frame,
    WFrame,
    RGBFrame,
    InputEvent,
    ControlEvent
  }

  @pubsub_topic "mixer"
  @pubsub_frames [Frame, WFrame, RGBFrame]
  @transition_duration 300
  @transition_frame_time trunc(1000 / 60)
  @playlist_id 3
  @game_time [0..94, 30..44] |> Enum.flat_map(&Enum.to_list/1)

  defmodule State do
    defstruct selected_app: nil,
              last_selected_app: nil,
              rendered_app: nil,
              transition: nil,
              buffer_canvas: Canvas.new(80, 8),
              max_luminance: 255,
              scheduling_active?: false,
              last_input: 0
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

  def handle_frame(app_id, %{} = frame) do
    # encode the frame in the app process, so any encoding errors get raised there
    Protobuf.encode(frame)
    |> send_frame(frame, app_id)
  end

  def handle_canvas(app_id, canvas) do
    GenServer.cast(__MODULE__, {:new_canvas, {app_id, canvas}})
  end

  defp send_frame(binary, frame, app_id) do
    GenServer.cast(__MODULE__, {:new_frame, {app_id, binary, frame}})
  end

  def handle_input(%InputEvent{} = input_event) do
    GenServer.cast(__MODULE__, {:input_event, input_event})
  end

  def handle_input(%SoundToLightControlEvent{} = stl_event) do
    GenServer.cast(__MODULE__, {:sound_to_light_control_event, stl_event})
  end

  @doc """
  Selects the app with the given `app_id`.
  """
  def select_app(app_id) do
    GenServer.cast(__MODULE__, {:select_app, app_id})
  end

  def select_app(app_id, side) when side in [:left, :right] do
    GenServer.cast(__MODULE__, {:select_app, app_id, side})
  end

  @doc """
  Returns the currently selected app.
  """
  def get_selected_app() do
    GenServer.call(__MODULE__, :get_selected_app)
  end

  def set_scheduling(active?) when is_boolean(active?) do
    GenServer.cast(__MODULE__, {:set_scheduling, active?})
  end

  def scheduling_active? do
    GenServer.call(__MODULE__, :scheduling_active?)
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
    PlaylistScheduler.start_playlist(@playlist_id)

    state = %State{
      last_input: System.os_time(:second)
    }

    set_scheduling(true)

    {:ok, state}
  end

  def handle_call(:get_selected_app, _, %State{selected_app: selected_app} = state) do
    {:reply, selected_app, state}
  end

  def handle_call(:scheduling_active?, _, %State{scheduling_active?: scheduling_active?} = state) do
    {:reply, scheduling_active?, state}
  end

  def handle_cast({:new_frame, {app_id, binary, f}}, %State{rendered_app: rendered_app} = state) do
    case rendered_app do
      {^app_id, _} -> send_frame(binary, f)
      {_, ^app_id} -> send_frame(binary, f)
      ^app_id -> send_frame(binary, f)
      _ -> :noop
    end

    {:noreply, state}
  end

  def handle_cast(
        {:new_canvas, {left_app_id, canvas}},
        %State{rendered_app: {left_app_id, _}} = state
      ) do
    handle_new_canvas(state, canvas, {0, 0})
  end

  def handle_cast(
        {:new_canvas, {right_app_id, canvas}},
        %State{rendered_app: {_, right_app_id}} = state
      ) do
    handle_new_canvas(state, canvas, {40, 0})
  end

  def handle_cast({:new_canvas, _}, state), do: {:noreply, state}

  def handle_cast({:input_event, %InputEvent{} = input_event}, %State{} = state) do
    state =
      %State{state | last_input: System.os_time(:second)}
      |> do_handle_input(input_event)

    {:noreply, state}
  end

  def handle_cast(
        {:sound_to_light_control_event, %SoundToLightControlEvent{} = stl_event},
        %State{} = state
      ) do
    AppSupervisor.send_event(state.selected_app, stl_event)

    {:noreply, state}
  end

  def handle_cast({:select_app, next_app_id, side}, %State{} = state) do
    selected_app =
      case {state.selected_app, side} do
        {{_, right}, :left} -> {next_app_id, right}
        {{left, _}, :right} -> {left, next_app_id}
        {_, :left} -> {next_app_id, nil}
        {_, :right} -> {nil, next_app_id}
      end

    state = %State{
      state
      | transition: nil,
        selected_app: selected_app,
        rendered_app: selected_app
    }

    broadcast_rendered_app(state)
    broadcast_selected_app(state)

    {:noreply, state}
  end

  def handle_cast(:stop_audio_playback, state) do
    do_stop_audio_playback()
    {:noreply, state}
  end

  defp handle_new_canvas(%State{} = state, %Canvas{} = canvas, offset) do
    new_canvas =
      canvas
      |> Canvas.cut({0, 0}, {39, 7})

    buffer_canvas =
      state.buffer_canvas
      |> Canvas.overlay(new_canvas, offset: offset, transparency: false)

    frame =
      buffer_canvas
      |> Canvas.to_frame()

    Protobuf.split_and_encode(frame)
    |> Enum.each(fn binary ->
      send_frame(binary, frame)
    end)

    state = maybe_stop_game_scheduler(state)

    {:noreply, %State{state | buffer_canvas: buffer_canvas}}
  end

  ### App Transitions ###
  # Implemented with a simple state machine that is represented by the `transition` field in the state.
  # Possible values are `{:in, time_left}`, `{:out, time_left}` and `nil`.
  def handle_cast({:select_app, next_app_id}, %State{transition: nil} = state) do
    state = %State{
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
    broadcast_rendered_app(state)
    {:noreply, state}
  end

  def handle_cast({:select_app, next_app_id}, %State{transition: {:in, time_left}} = state) do
    state = %State{
      state
      | transition: {:out, @transition_duration - time_left},
        selected_app: next_app_id,
        last_selected_app: state.selected_app
    }

    broadcast_selected_app(state)

    {:noreply, state}
  end

  def handle_cast({:set_scheduling, active?}, %State{} = state) do
    if active? do
      Logger.info("Starting scheduling")
      PlaylistScheduler.start_playlist(@playlist_id)
    else
      Logger.info("Stopping scheduling")

      GameScheduler.stop()
      PlaylistScheduler.stop_playlist()
    end

    Phoenix.PubSub.broadcast(
      Octopus.PubSub,
      @pubsub_topic,
      {:mixer, {:scheduling_active, active?}}
    )

    state = %State{state | scheduling_active?: active?}
    {:noreply, state}
  end

  def handle_info(:transition, %State{transition: nil} = state) do
    {:noreply, state}
  end

  def handle_info(:transition, %State{transition: {:out, time}} = state) when time <= 0 do
    state = %State{
      state
      | rendered_app: state.selected_app,
        transition: {:in, @transition_duration}
    }

    Broadcaster.set_luminance(0)

    broadcast_rendered_app(state)

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
  defp send_frame(binary, %frame_type{} = frame) do
    if frame_type in @pubsub_frames do
      Phoenix.PubSub.broadcast(Octopus.PubSub, @pubsub_topic, {:mixer, {:frame, frame}})
    end

    Broadcaster.send_binary(binary)
  end

  defp schedule_transition() do
    Process.send_after(self(), :transition, @transition_frame_time)
  end

  defp broadcast_selected_app(%State{} = state) do
    selected =
      case state.selected_app do
        {_, _} -> nil
        app_id -> app_id
      end

    Phoenix.PubSub.broadcast(
      Octopus.PubSub,
      @pubsub_topic,
      {:mixer, {:selected_app, selected}}
    )
  end

  defp broadcast_rendered_app(%State{selected_app: {_, _}} = state), do: state

  defp broadcast_rendered_app(%State{} = state) do
    do_stop_audio_playback()
    AppSupervisor.send_event(state.selected_app, %ControlEvent{type: :APP_SELECTED})
    AppSupervisor.send_event(state.last_selected_app, %ControlEvent{type: :APP_DESELECTED})
  end

  def stop_audio_playback() do
    GenServer.cast(__MODULE__, :stop_audio_playback)
  end

  defp do_handle_input(
         %State{scheduling_active?: true} = state,
         %InputEvent{type: :BUTTON_MENU, value: 1}
       ) do
    case DateTime.utc_now() do
      %DateTime{minute: minute} when minute in @game_time ->
        PlaylistScheduler.stop_playlist()
        GameScheduler.start()

      _ ->
        :noop
    end

    state
  end

  defp do_handle_input(state, %InputEvent{type: :BUTTON_MENU}), do: state

  defp do_handle_input(%State{} = state, %InputEvent{} = input_event) do
    maybe_set_next_game(input_event)

    case state.selected_app do
      {left, right} ->
        AppSupervisor.send_event(left, input_event)
        AppSupervisor.send_event(right, input_event)

      app_id ->
        AppSupervisor.send_event(app_id, input_event)
    end

    state
  end

  defp maybe_stop_game_scheduler(%State{scheduling_active?: true} = state) do
    %DateTime{minute: minute} = DateTime.utc_now()

    if minute not in @game_time or state.last_input < System.os_time(:second) - 60 do
      GameScheduler.stop()
      PlaylistScheduler.start_playlist(@playlist_id)
      state
    else
      state
    end
  end

  defp maybe_stop_game_scheduler(state), do: state

  defp do_stop_audio_playback do
    1..10
    |> Enum.map(&%AudioFrame{stop: true, channel: &1})
    |> Enum.map(&Protobuf.encode/1)
    |> Enum.each(&Broadcaster.send_binary/1)
  end

  defp maybe_set_next_game(%InputEvent{type: :BUTTON_5, value: 1}) do
    GameScheduler.next_game(:left)
  end

  defp maybe_set_next_game(%InputEvent{type: :BUTTON_6, value: 1}) do
    GameScheduler.next_game(:right)
  end

  defp maybe_set_next_game(_), do: :noop
end
