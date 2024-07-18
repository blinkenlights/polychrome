defmodule Octopus.PlaylistScheduler do
  use GenServer
  require Logger

  alias Octopus.{AppSupervisor, Mixer, Repo}
  alias Octopus.PlaylistScheduler.Playlist
  alias Octopus.PlaylistScheduler.Playlist.Animation

  @topic "playlist_scheduler"
  @default_animation %{app: "Text", config: %{text: "POLYCHROME"}, timeout: 60_000}

  defmodule State do
    defstruct [:playlist_id, :run_id, :index, :app_id]
  end

  defmodule Status do
    defstruct [:playlist, :index, :status]
  end

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def subscribe() do
    Phoenix.PubSub.subscribe(Octopus.PubSub, @topic)
    broadcast()
  end

  def start_playlist(id) do
    GenServer.cast(__MODULE__, {:start, id})
  end

  def stop_playlist() do
    GenServer.cast(__MODULE__, :stop)
  end

  def create_playlist!(name) do
    %Playlist{}
    |> Playlist.changeset(%{name: name, animations: [@default_animation]})
    |> Repo.insert!()
  end

  def list_playlists() do
    Repo.all(Playlist)
  end

  def delete_playlist!(%Playlist{} = playlist) do
    playlist
    |> Repo.delete!()
  end

  def update_playlist!(id, attrs) do
    get_playlist(id)
    |> Playlist.changeset(attrs)
    |> Repo.update!()
  end

  def get_playlist(id) do
    Repo.get(Playlist, id)
  end

  def selected_playlist() do
    GenServer.call(__MODULE__, :selected_playlist)
  end

  def playlist_next() do
    GenServer.cast(__MODULE__, :next_animation)
  end

  def playlist_previous() do
    GenServer.cast(__MODULE__, :prev_animation)
  end

  def broadcast() do
    GenServer.cast(__MODULE__, :broadcast_status)
  end

  def init(:ok) do
    {:ok, %State{}}
  end

  def handle_cast({:start, id}, %State{} = state) do
    case get_playlist(id) do
      playlist = %Playlist{} ->
        index = length(playlist.animations) - 1
        Logger.info("Starting playlist #{inspect(playlist.name)}")

        state =
          %State{state | playlist_id: id, index: index}
          |> new_run_id()
          |> broadcast_status()

        send(self(), {:next, state.run_id})

        {:noreply, state}

      nil ->
        Logger.warning("Playlist id #{id} not found")
        {:noreply, state}
    end
  end

  def handle_cast(:stop, %State{} = state) do
    Logger.info("Stopping playlist")

    if state.app_id != nil do
      AppSupervisor.stop_app(state.app_id)
    end

    {:noreply, %State{state | app_id: nil, run_id: nil} |> broadcast_status()}
  end

  def handle_cast(:broadcast_status, %State{} = state) do
    broadcast_status(state)
    {:noreply, state}
  end

  def handle_cast(:next_animation, %State{run_id: nil} = state), do: {:noreply, state}

  def handle_cast(:next_animation, %State{} = state) do
    state = state |> new_run_id()

    send(self(), {:next, state.run_id})
    {:noreply, state |> broadcast_status()}
  end

  def handle_cast(:prev_animation, %State{run_id: nil} = state), do: {:noreply, state}

  def handle_cast(:prev_animation, %State{} = state) do
    playlist = %Playlist{} = get_playlist(state.playlist_id)

    state =
      %State{state | index: Integer.mod(state.index - 2, length(playlist.animations))}
      |> new_run_id()

    send(self(), {:next, state.run_id})

    {:noreply, state |> broadcast_status()}
  end

  def handle_call(:selected_playlist, _from, %State{playlist_id: playlist_id} = state) do
    {:reply, playlist_id, state}
  end

  def handle_info({:next, run_id}, %State{run_id: run_id} = state) do
    playlist = %Playlist{} = get_playlist(state.playlist_id)
    next_index = rem(state.index + 1, length(playlist.animations))

    animation = %Animation{} = Enum.at(playlist.animations, next_index)

    config =
      animation.config
      |> Enum.map(fn {k, v} -> {String.to_atom(k), v} end)
      |> Enum.into(%{})

    module = Module.concat(Octopus.Apps, animation.app)

    Logger.info(
      "Scheduling next app #{module} with config #{inspect(config)}. Timeout: #{animation.timeout}"
    )

    {:ok, next_app_id} = AppSupervisor.start_app(module, config: config)
    Mixer.select_app(next_app_id)
    AppSupervisor.stop_app(state.app_id)

    :timer.send_after(animation.timeout, self(), {:next, run_id})

    {:noreply, %State{state | index: next_index, app_id: next_app_id} |> broadcast_status()}
  end

  def handle_info({:next, _}, state) do
    {:noreply, state}
  end

  defp broadcast_status(%State{playlist_id: nil} = state) do
    status = %Status{playlist: nil, index: nil, status: :stopped}
    Phoenix.PubSub.broadcast(Octopus.PubSub, @topic, {:playlist, status})
    state
  end

  defp broadcast_status(%State{app_id: nil} = state) do
    status =
      %Status{
        playlist: get_playlist(state.playlist_id),
        index: state.index,
        status: :stopped
      }

    Phoenix.PubSub.broadcast(Octopus.PubSub, @topic, {:playlist, status})
    state
  end

  defp broadcast_status(%State{} = state) do
    status =
      %Status{
        playlist: get_playlist(state.playlist_id),
        index: state.index,
        status: :running
      }

    Phoenix.PubSub.broadcast(Octopus.PubSub, @topic, {:playlist, status})
    state
  end

  defp new_run_id(%State{} = state) do
    run_id = :crypto.strong_rand_bytes(16)
    %State{state | run_id: run_id}
  end
end
