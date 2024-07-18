defmodule Octopus.EventScheduler do
  use GenServer
  require Logger

  alias Octopus.{AppSupervisor, Mixer, PlaylistScheduler}
  alias Octopus.Protobuf.InputEvent

  @game Octopus.Apps.Whackamole
  @playlist_id 5

  defmodule State do
    defstruct game_app_id: nil,
              # statuses: :game, :playlist, :off
              status: :off
  end

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def start() do
    GenServer.cast(__MODULE__, :start)
  end

  def stop() do
    GenServer.cast(__MODULE__, :stop)
  end

  def handle_input(%InputEvent{} = input_event) do
    GenServer.cast(__MODULE__, {:input_event, input_event})
  end

  def game_finished() do
    GenServer.cast(__MODULE__, :game_finished)
  end

  def init(:ok) do
    status =
      case Application.fetch_env(:octopus, :enable_event_mode) do
        {:ok, true} ->
          start_playlist()
          :playlist

        _ ->
          :off
      end

    Logger.info("EventScheduler: starting in #{status} mode")
    {:ok, %State{status: status}}
  end

  def handle_cast(:start, %State{status: :off} = state) do
    start_playlist()
    {:noreply, %State{state | status: :playlist}}
  end

  def handle_cast(:start, state), do: {:noreply, state}

  def handle_cast(:stop, %State{} = state) do
    AppSupervisor.stop_app(state.game_app_id)
    PlaylistScheduler.stop_playlist()

    {:noreply, %State{state | status: :off}}
  end

  @activate_game_buttons [
    :BUTTON_1,
    :BUTTON_2,
    :BUTTON_3,
    :BUTTON_4,
    :BUTTON_5,
    :BUTTON_6,
    :BUTTON_7,
    :BUTTON_8,
    :BUTTON_9,
    :BUTTON_10
  ]

  def handle_cast(
        {:input_event, %InputEvent{type: type, value: 1}},
        %State{status: :playlist} = state
      )
      when type in @activate_game_buttons do
    Logger.info("EventScheduler: game button pressed, starting game")

    PlaylistScheduler.stop_playlist()
    {:ok, app_id} = AppSupervisor.start_app(@game)
    Mixer.select_app(app_id)

    {:noreply, %State{state | status: :game, game_app_id: app_id}}
  end

  def handle_cast({:input_event, %InputEvent{}}, state) do
    {:noreply, state}
  end

  def handle_cast(:game_finished, %State{status: :game} = state) do
    Logger.info("EventScheduler: game finished, starting playlist")

    AppSupervisor.stop_app(state.game_app_id)
    start_playlist()

    {:noreply, %State{state | status: :playlist}}
  end

  def handle_cast(:game_finished, state), do: {:noreply, state}

  defp start_playlist() do
    PlaylistScheduler.start_playlist(@playlist_id)
  end
end
