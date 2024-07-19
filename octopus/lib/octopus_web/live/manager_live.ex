defmodule OctopusWeb.ManagerLive do
  use OctopusWeb, :live_view

  alias Octopus.Canvas
  alias Octopus.Layout.Mildenberg
  alias Octopus.{Mixer, AppSupervisor, PlaylistScheduler}
  alias Octopus.PlaylistScheduler.Playlist
  alias Octopus.PlaylistScheduler.Playlist.Animation
  alias OctopusWeb.PixelsLive

  def mount(_params, _session, socket) do
    if connected?(socket) do
      AppSupervisor.subscribe()
      PlaylistScheduler.subscribe()
    end

    socket =
      socket
      |> setup_preview(Application.fetch_env!(:octopus, :show_sim_preview))
      |> assign_apps()
      |> assign(playlist_status: nil)
      |> assign(playlist_selected_id: nil)
      |> assign_playlists()

    {:ok, socket, temporary_assigns: [pixel_layout: nil]}
  end

  defp setup_preview(socket, true) do
    Mixer.subscribe()

    socket
    |> assign(pixel_layout: Mildenberg.layout())
    |> assign(show_sim_preview: true)
  end

  defp setup_preview(socket, false) do
    socket
    |> assign(show_sim_preview: false)
  end

  def render(assigns) do
    ~H"""
    <div class="w-full" phx-window-keydown="keydown-event">
      <%= if @show_sim_preview do %>
        <div class="flex w-full h-full justify-center bg-black">
          <%= live_render(@socket, PixelsLive, id: "main") %>
        </div>
      <% end %>

      <div class="container mx-auto">
        <%!-- Playlists --%>
        <div class="border rounded m-2 p-0">
          <div class="flex flex-row">
            <div class="p-1 font-bold m-0 flex-grow">
              Playlists
            </div>
            <div>
              <button
                class="text-slate-800 background-transparent font-bold uppercase px-3 py-1 text-xs outline-none focus:outline-none mr-1 mb-1 ease-linear transition-all duration-150"
                type="button"
                phx-click="playlist-new"
              >
                New Playlist
              </button>
            </div>
          </div>
          <table class="w-full text-left m-0">
            <tbody>
              <tr :for={{playlist_id, name} <- @playlists}>
                <td class={"w-1/2 p-2 #{if playlist_id == @playlist_selected_id, do: "bg-slate-300 font-bold"}"}>
                  <%= if playlist_id == @playlist_selected_id do %>
                    <div class="flex flex-row flex-wrap gap-2">
                      <%= name %>
                      <div :if={playlist_id == @playlist_selected_id}>
                        <div class={
                          if @playlist_status && @playlist_status.status == :running,
                            do: "text-green-600",
                            else: "text-red-600"
                        }>
                          <%= if @playlist_status, do: @playlist_status.status %>
                        </div>
                      </div>
                    </div>
                  <% else %>
                    <%= name %>
                  <% end %>
                </td>
                <td class="p-2 flex flex-row flex-wrap gap-2">
                  <button
                    class="border py-1 px-2 rounded bg-slate-500 text-white flex flex-row items-center gap-1"
                    phx-click="playlist-start"
                    phx-value-playlist-id={playlist_id}
                  >
                    ▶
                  </button>
                  <button
                    class={[
                      "border py-1 px-2 rounded bg-slate-500 text-white flex flex-row items-center gap-1",
                      playlist_id == @playlist_selected_id || "opacity-50"
                    ]}
                    phx-click="playlist-stop"
                    phx-value-playlist-id={playlist_id}
                    disabled={playlist_id != @playlist_selected_id}
                  >
                    ⏹︎
                  </button>
                  <button
                    class={[
                      "border py-1 px-2 rounded bg-slate-500 text-white flex flex-row items-center gap-1",
                      playlist_id == @playlist_selected_id || "opacity-50"
                    ]}
                    phx-click="playlist-prev"
                    phx-value-playlist-id={playlist_id}
                    disabled={playlist_id != @playlist_selected_id}
                  >
                    ⏮
                  </button>
                  <button
                    class={[
                      "border py-1 px-2 rounded bg-slate-500 text-white flex flex-row items-center gap-1",
                      playlist_id == @playlist_selected_id || "opacity-50"
                    ]}
                    phx-click="playlist-next"
                    phx-value-playlist-id={playlist_id}
                    disabled={playlist_id != @playlist_selected_id}
                  >
                    ⏭
                  </button>
                  <.link
                    class="border py-1 px-2 rounded bg-slate-500 text-white flex flex-row items-center gap-1"
                    navigate={~p"/playlist/#{playlist_id}"}
                  >
                    ✎
                  </.link>
                  <button
                    class="border py-1 px-2 rounded bg-slate-500 text-white flex flex-row items-center gap-1"
                    phx-click="playlist-delete"
                    phx-value-playlist-id={playlist_id}
                  >
                    🗑
                  </button>
                </td>
              </tr>
            </tbody>
          </table>

          <div :if={@playlist_status && @playlist_status.playlist} class="m-2 border-4">
            <table class="w-full text-left m-0">
              <tbody>
                <tr
                  :for={
                    {%Animation{app: app, config: config, timeout: timeout}, index} <-
                      Enum.with_index(@playlist_status.playlist.animations)
                  }
                  class={index != @playlist_status.index || "bg-slate-200 font-bold"}
                >
                  <td class="w-1/4 p-2">
                    <%= app %>
                  </td>
                  <td><%= timeout %></td>
                  <td class="w-1/2 "><%= config |> Jason.encode!() %></td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

        <%!-- Running Apps --%>
        <div class="border rounded m-2 p-0">
          <div class="flex flex-row">
            <div class="p-1 font-bold m-0 flex-grow">
              Running Apps
            </div>
            <div>
              <a href="/sim">
                <button
                  class="text-slate-800 background-transparent font-bold uppercase px-3 py-1 text-xs outline-none focus:outline-none mr-1 mb-1 ease-linear transition-all duration-150"
                  type="button"
                >
                  Open Sim
                </button>
              </a>
            </div>
          </div>
          <table class="w-full text-left m-0">
            <tbody>
              <tr :for={
                %{module: module, app_id: app_id, name: name, selected: selected} <-
                  @running_apps
              }>
                <td class={"w-1/2 p-2 #{if selected, do: ~c"bg-slate-300 font-bold"}"}>
                  <%= name %>
                </td>
                <td class="flex flex-row gap-2 p-1 pl-3">
                  <button
                    class="border py-1 px-2 rounded  bg-slate-300"
                    phx-click="stop"
                    phx-value-module={module}
                    phx-value-app-id={app_id}
                  >
                    Stop
                  </button>

                  <.link navigate={~p"/app/#{app_id}"} class="border py-1 px-2 rounded bg-slate-300">
                    Configure
                  </.link>

                  <button
                    :if={!selected}
                    class="border py-1 px-2 rounded bg-slate-300"
                    phx-click="select"
                    phx-value-module={module}
                    phx-value-app-id={app_id}
                  >
                    Select
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <div :for={{category, apps} <- @available_apps}>
          <div class="flex flex-col m-2">
            <div class="p-2 font-bold">
              <%= category |> to_string |> String.capitalize() %> Apps
            </div>
            <div class="border p-2 flex flex-row flex-wrap">
              <div :for={%{module: module, name: name, icon: icon} <- apps} class="m-0 p-1">
                <button
                  class="border py-1 px-2 rounded bg-slate-500 text-white flex flex-row items-center gap-1"
                  phx-click="start"
                  phx-value-module={module}
                >
                  <%= if icon do %>
                    <div class="w-5 h-5 inline-block rounded-sm overflow-hidden">
                      <%= raw(icon) %>
                    </div>
                  <% end %>
                  <%= name %>
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def handle_event("start", %{"module" => module_string}, socket) do
    module = String.to_existing_atom(module_string)
    {:ok, app_id} = AppSupervisor.start_app(module)
    Mixer.select_app(app_id)
    {:noreply, socket}
  end

  def handle_event("stop", %{"app-id" => app_id}, socket) do
    AppSupervisor.stop_app(app_id)

    {:noreply, socket}
  end

  def handle_event("select", %{"app-id" => app_id}, socket) do
    Mixer.select_app(app_id)
    {:noreply, socket}
  end

  def handle_event("keydown-event", %{"key" => _other_key}, socket) do
    {:noreply, socket}
  end

  def handle_event("configure", %{"app-id" => app_id}, socket) do
    {:noreply, socket |> assign(configure_app: app_id)}
  end

  # todo: playlist-update

  def handle_event("playlist-start", %{"playlist-id" => id}, socket) do
    PlaylistScheduler.start_playlist(id)

    {:noreply, socket}
  end

  def handle_event("playlist-new", _params, socket) do
    %Playlist{id: id} = PlaylistScheduler.create_playlist!("Playlist_#{System.os_time(:second)}")

    socket =
      socket
      |> push_navigate(to: ~p"/playlist/#{id}")

    {:noreply, socket}
  end

  def handle_event("playlist-delete", %{"playlist-id" => id}, socket) do
    playlist = PlaylistScheduler.get_playlist(id)
    PlaylistScheduler.delete_playlist!(playlist)

    socket =
      socket
      |> put_flash(:info, "Playlist #{playlist.name} deleted")
      |> assign_playlists()

    {:noreply, socket}
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

  def handle_info({:apps, _}, socket) do
    {:noreply, socket |> assign_apps()}
  end

  def handle_info({:mixer, {:selected_app, _selected_app_id}}, socket) do
    {:noreply, socket |> assign_apps()}
  end

  def handle_info({:mixer, {:frame, _frame}}, socket) do
    {:noreply, socket}
  end

  def handle_info({:mixer, {:config, _config}}, socket) do
    {:noreply, socket}
  end

  def handle_info({:playlist, status = %PlaylistScheduler.Status{}}, socket) do
    id =
      case status.playlist do
        %Playlist{id: id} -> id
        _ -> nil
      end

    socket =
      socket
      |> assign(playlist_status: status)
      |> assign(playlist_selected_id: id)

    {:noreply, socket}
  end

  defp assign_apps(socket) do
    available_apps =
      for module <- AppSupervisor.available_apps() do
        name = apply(module, :name, [])

        icon =
          case apply(module, :icon, []) do
            nil -> nil
            canvas -> Canvas.to_svg(canvas, width: "100%", height: "100%")
          end

        category = apply(module, :category, [])

        %{module: module, name: name, icon: icon, category: category}
      end
      |> Enum.group_by(& &1.category)
      |> Enum.sort_by(fn {category, _} ->
        Map.get(%{animation: 0, game: 1, test: 2, misc: 3}, category, 99)
      end)

    selected_app = Mixer.get_selected_app()

    running_apps =
      for {module, app_id} <- AppSupervisor.running_apps() do
        %{
          module: module,
          app_id: app_id,
          name: apply(module, :name, []),
          selected: app_id == selected_app
        }
      end

    socket |> assign(available_apps: available_apps, running_apps: running_apps)
  end

  def assign_playlists(socket) do
    playlists =
      PlaylistScheduler.list_playlists()
      |> Enum.map(fn %Playlist{id: id, name: name} -> {id, name} end)

    socket
    |> assign(playlists: playlists)
  end
end
