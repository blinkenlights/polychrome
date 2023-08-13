defmodule OctopusWeb.ManagerLive do
  use OctopusWeb, :live_view

  alias Phoenix.LiveView.Socket
  alias Octopus.Canvas
  alias Octopus.Layout.Mildenberg
  alias Octopus.{Mixer, AppSupervisor, PlaylistScheduler}
  alias Octopus.PlaylistScheduler.Playlist
  alias OctopusWeb.PixelsLive

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Mixer.subscribe()
      AppSupervisor.subscribe()
      PlaylistScheduler.subscribe()
    end

    socket =
      socket
      |> assign(pixel_layout: Mildenberg.layout(), configure_app: nil)
      |> assign(playlist_status: "")
      |> assign(selected_playlist: nil)
      |> assign_apps()
      |> assign_playlist_options()

    {:ok, socket, temporary_assigns: [pixel_layout: nil]}
  end

  def render(assigns) do
    ~H"""
    <div class="w-full" phx-window-keydown="keydown-event">
      <div class="flex w-full h-full justify-center bg-black">
        <%= live_render(@socket, PixelsLive, id: "main") %>
      </div>

      <div class="container mx-auto">
        <div class="border rounded m-2 p-0">
          <div class="flex flex-row">
            <div class="p-1 font-bold m-0 flex-grow">
              Running:
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
                %{module: module, app_id: app_id, name: name, selected: selected} <- @running_apps
              }>
                <td class={"p-2 #{if selected, do: 'bg-slate-300 font-bold'}"}><%= name %></td>
                <td class={"p-2 #{if selected, do: 'bg-slate-300 font-bold'}"}><%= app_id %></td>
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

        <div class="flex flex-col m-2">
          <div class="p-2 font-bold">
            Playlist Scheduler
          </div>
          <div class="border p-2 flex flex-row flex-wrap">
            <form phx-change="playlist-selected">
              <select name="playlist">
                <option
                  :for={{id, name} <- @playlist_options}
                  value={id}
                  selected={id == @selected_playlist}
                >
                  <%= name %>
                </option>
              </select>
            </form>

            <button
              class="border py-1 px-2 rounded bg-slate-500 text-white flex flex-row items-center gap-1"
              phx-click="playlist-start"
            >
              ▶
            </button>
            <button
              class="border py-1 px-2 rounded bg-slate-500 text-white flex flex-row items-center gap-1"
              phx-click="playlist-stop"
            >
              ⏹︎
            </button>
            <button
              class="border py-1 px-2 rounded bg-slate-500 text-white flex flex-row items-center gap-1"
              phx-click="playlist-edit"
            >
              ✎
            </button>
            <button
              class="border py-1 px-2 rounded bg-slate-500 text-white flex flex-row items-center gap-1"
              phx-click="playlist-delete"
            >
              🗑
            </button>
            <p class="px-4 py-2"><%= @playlist_status %></p>
            <button
              class="border py-1 px-2 rounded bg-slate-500 text-white flex flex-row items-center gap-1"
              phx-click="playlist-new"
            >
              New
            </button>
          </div>
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
    {:ok, _} = AppSupervisor.start_app(module)
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

  def handle_event("playlist-selected", %{"playlist" => id}, socket) do
    socket =
      socket
      |> assign(selected_playlist: id)

    {:noreply, socket}
  end

  def handle_event("playlist-new", _params, socket) do
    %Playlist{id: id} = PlaylistScheduler.create_playlist!("Playlist_#{System.os_time(:second)}")

    socket =
      socket
      |> redirect(to: ~p"/playlist/#{id}")

    {:noreply, socket}
  end

  def handle_event("playlist-" <> _, _, %Socket{assigns: %{selected_playlist: nil}} = socket) do
    socket =
      socket
      |> put_flash(:error, "No playlist selected")

    {:noreply, socket}
  end

  def handle_event("playlist-start", _params, socket) do
    Scheduler.start()
    {:noreply, socket}
  end

  def handle_event("playlist-stop", _params, socket) do
    Scheduler.stop()
    {:noreply, socket}
  end

  def handle_event("playlist-edit", _params, socket) do
    socket =
      socket
      |> redirect(to: ~p"/playlist/#{socket.assigns.selected_playlist}")

    {:noreply, socket}
  end

  def handle_event("playlist-delete", _params, socket) do
    playlist = %Playlist{} = PlaylistScheduler.get_playlist(socket.assigns.selected_playlist)

    PlaylistScheduler.delete_playlist!(playlist)

    socket =
      socket
      |> put_flash(:info, "Playlist #{playlist.name} deleted")
      |> assign_playlist_options()

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

  def handle_info({:scheduler, status}, socket) do
    str =
      case status do
        {:running, app_id} -> "Running #{app_id}"
        :stopped -> "Stopped"
      end

    {:noreply, assign(socket, playlist_status: str)}
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

  def assign_playlist_options(socket) do
    playlist_options =
      PlaylistScheduler.list_playlists()
      |> Enum.map(fn %Playlist{id: id, name: name} -> {id, name} end)

    socket
    |> assign(playlist_options: playlist_options)
  end
end
