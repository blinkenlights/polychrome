defmodule OctopusWeb.PlaylistsLive do
  use OctopusWeb, :live_view

  alias Octopus.PlaylistScheduler
  alias Octopus.PlaylistScheduler.Playlist
  alias Octopus.PlaylistScheduler.Playlist.Animation

  def mount(_params, _session, socket) do
    if connected?(socket), do: PlaylistScheduler.subscribe()

    socket =
      socket
      |> assign(playlist_status: nil, playlist_selected_id: nil)
      |> assign_playlists()

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="container mx-auto py-6">
      <.link navigate={~p"/"} class="link link-hover text-sm mb-4 inline-block">← Back to console</.link>

      <div class="card bg-base-200 shadow-md">
        <div class="card-body">
          <h1 class="card-title">Playlist scheduler</h1>
          <div class="card-actions">
            <button class="btn btn-primary btn-sm" type="button" phx-click="playlist-new">
              New Playlist
            </button>
          </div>
          <table class="table table-zebra w-full">
            <tbody>
              <tr :for={{playlist_id, name} <- @playlists}>
                <td class={if playlist_id == @playlist_selected_id, do: "font-bold"}>
                  <div class="flex flex-row flex-wrap gap-2 items-center">
                    {name}
                    <span
                      :if={playlist_id == @playlist_selected_id && @playlist_status}
                      class={[
                        "badge badge-sm",
                        @playlist_status.status == :running && "badge-success",
                        @playlist_status.status != :running && "badge-error"
                      ]}
                    >
                      {@playlist_status.status}
                    </span>
                  </div>
                </td>
                <td class="flex flex-row flex-wrap gap-2">
                  <button class="btn btn-primary btn-sm" phx-click="playlist-start" phx-value-playlist-id={playlist_id}>
                    ▶
                  </button>
                  <button
                    class={["btn btn-secondary btn-sm", playlist_id != @playlist_selected_id && "btn-disabled"]}
                    phx-click="playlist-stop"
                    disabled={playlist_id != @playlist_selected_id}
                  >
                    ⏹︎
                  </button>
                  <button
                    class={["btn btn-outline btn-sm", playlist_id != @playlist_selected_id && "btn-disabled"]}
                    phx-click="playlist-prev"
                    disabled={playlist_id != @playlist_selected_id}
                  >
                    ⏮
                  </button>
                  <button
                    class={["btn btn-outline btn-sm", playlist_id != @playlist_selected_id && "btn-disabled"]}
                    phx-click="playlist-next"
                    disabled={playlist_id != @playlist_selected_id}
                  >
                    ⏭
                  </button>
                  <.link class="btn btn-accent btn-sm" navigate={~p"/playlist/#{playlist_id}"}>
                    ✎
                  </.link>
                  <button class="btn btn-error btn-sm" phx-click="playlist-delete" phx-value-playlist-id={playlist_id}>
                    🗑
                  </button>
                </td>
              </tr>
            </tbody>
          </table>

          <div :if={@playlist_status && @playlist_status.playlist} class="mt-4 border border-base-300 rounded-lg overflow-hidden">
            <table class="w-full text-left text-sm">
              <tbody>
                <tr
                  :for={
                    {%Animation{app: app, config: config, timeout: timeout}, index} <-
                      Enum.with_index(@playlist_status.playlist.animations)
                  }
                  class={index == @playlist_status.index && "bg-base-300 font-bold"}
                >
                  <td class="p-2 w-1/4">{app}</td>
                  <td class="p-2">{timeout}</td>
                  <td class="p-2 w-1/2">{config |> JSON.encode!()}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def handle_event("playlist-start", %{"playlist-id" => id}, socket) do
    PlaylistScheduler.start_playlist(id)
    {:noreply, socket}
  end

  def handle_event("playlist-new", _params, socket) do
    %Playlist{id: id} = PlaylistScheduler.create_playlist!("Playlist_#{System.os_time(:second)}")
    {:noreply, push_navigate(socket, to: ~p"/playlist/#{id}")}
  end

  def handle_event("playlist-delete", %{"playlist-id" => id}, socket) do
    playlist = PlaylistScheduler.get_playlist(id)
    PlaylistScheduler.delete_playlist!(playlist)

    {:noreply, socket |> put_flash(:info, "Playlist #{playlist.name} deleted") |> assign_playlists()}
  end

  def handle_event("playlist-stop", _params, socket) do
    PlaylistScheduler.pause_playlist()
    {:noreply, socket}
  end

  def handle_event("playlist-next", _params, socket) do
    PlaylistScheduler.playlist_next()
    {:noreply, socket}
  end

  def handle_event("playlist-prev", _params, socket) do
    PlaylistScheduler.playlist_previous()
    {:noreply, socket}
  end

  def handle_info({:playlist, status = %PlaylistScheduler.Status{}}, socket) do
    id =
      case status.playlist do
        %Playlist{id: id} -> id
        _ -> nil
      end

    {:noreply, assign(socket, playlist_status: status, playlist_selected_id: id)}
  end

  defp assign_playlists(socket) do
    playlists =
      PlaylistScheduler.list_playlists()
      |> Enum.map(fn %Playlist{id: id, name: name} -> {id, name} end)

    assign(socket, playlists: playlists)
  end
end
