defmodule Octopus.KioskModeManager do
  use GenServer
  require Logger

  alias Octopus.{AppSupervisor, AppManager, PlaylistScheduler}
  alias Octopus.Events.Event.Input, as: InputEvent
  alias Octopus.PlaylistScheduler.Playlist

  @game Octopus.Apps.OneWord
  @playlist_name "Default"

  @topic "kiosk_mode_manager"

  defmodule State do
    # statuses: :game, :playlist, :off
    defstruct status: :off,
              game_app_id: nil,
              playlist_id: nil
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

  def start_game() do
    GenServer.cast(__MODULE__, :start_game)
  end

  def game_finished() do
    GenServer.cast(__MODULE__, :game_finished)
  end

  def started?() do
    GenServer.call(__MODULE__, :started?)
  end

  @doc """
  Subscribes to the kiosk_mode_manager topic.

  Published messages:
  * `{:kiosk_mode_manager, :started}` - kiosk mode was started
  * `{:kiosk_mode_manager, :stopped}` - kiosk mode was stopped
  """

  def subscribe() do
    Phoenix.PubSub.subscribe(Octopus.PubSub, @topic)
  end

  def init(:ok) do
    case Application.fetch_env(:octopus, :enable_kiosk_mode) do
      {:ok, true} ->
        Logger.info("KioskModeManager: event mode enabled. Starting")
        start()

      _ ->
        :noop
    end

    playlist_id =
      PlaylistScheduler.list_playlists()
      |> Enum.find(fn %Playlist{name: name} -> name == @playlist_name end)
      |> case do
        %Playlist{id: id} ->
          Logger.info("KioskModeManager: using playlist #{@playlist_name} with id #{id}")
          id

        _ ->
          nil
      end

    {:ok, %State{status: :off, playlist_id: playlist_id}}
  end

  def handle_cast(:start, %State{status: :off} = state) do
    PlaylistScheduler.start_playlist(state.playlist_id)
    Phoenix.PubSub.broadcast(Octopus.PubSub, @topic, {:kiosk_mode_manager, :started})
    {:noreply, %State{state | status: :playlist}}
  end

  def handle_cast(:start, state) do
    {:noreply, state}
  end

  def handle_cast(:stop, %State{} = state) do
    AppSupervisor.stop_app(state.game_app_id)
    PlaylistScheduler.pause_playlist()
    Phoenix.PubSub.broadcast(Octopus.PubSub, @topic, {:kiosk_mode_manager, :stopped})
    {:noreply, %State{state | status: :off}}
  end

  # Start the game
  def handle_cast(:start_game, %State{status: :playlist} = state) do
    Logger.info("KioskModeManager: starting game")

    PlaylistScheduler.pause_playlist()
    {:ok, app_id} = AppSupervisor.start_app(@game)
    AppManager.select_app(app_id)

    {:noreply, %State{state | status: :game, game_app_id: app_id}}
  end

  def handle_cast(:start_game, state) do
    {:noreply, state}
  end

  def handle_cast({:input_event, %InputEvent{}}, state) do
    {:noreply, state}
  end

  def handle_cast(:game_finished, %State{status: :game} = state) do
    Logger.info("KioskModeManager: game finished, starting playlist")

    AppSupervisor.stop_app(state.game_app_id)
    PlaylistScheduler.resume_playlist()

    {:noreply, %State{state | status: :playlist}}
  end

  def handle_cast(:game_finished, state), do: {:noreply, state}

  def handle_call(:started?, _, %State{status: :off} = state), do: {:reply, false, state}
  def handle_call(:started?, _, state), do: {:reply, true, state}
end
