defmodule OctopusWeb.ManagerLive do
  use OctopusWeb, :live_view

  alias Octopus.Canvas
  alias Octopus.Layout.Mildenberg
  alias Octopus.{AppManager, AppSupervisor, PlaylistScheduler}
  alias Octopus.PlaylistScheduler.Playlist
  alias Octopus.PlaylistScheduler.Playlist.Animation
  alias Octopus.KioskModeManager
  alias Octopus.Radar
  alias OctopusWeb.PixelsLive

  def mount(_params, _session, socket) do
    if connected?(socket) do
      AppSupervisor.subscribe()
      PlaylistScheduler.subscribe()
      KioskModeManager.subscribe()
      AppManager.subscribe()
      Octopus.Params.Global.subscribe()
    end

    socket =
      socket
      |> setup_preview(Application.fetch_env!(:octopus, :show_sim_preview))
      |> assign_apps()
      |> assign(playlist_status: nil)
      |> assign(playlist_selected_id: nil)
      |> assign(event_scheduler_started: KioskModeManager.started?())
      |> assign_playlists()

    {:ok, socket, temporary_assigns: [pixel_layout: nil]}
  end

  defp setup_preview(socket, true) do
    Octopus.Mixer.subscribe()

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
          {live_render(@socket, PixelsLive, id: "main")}
        </div>
      <% end %>

      <div class="container mx-auto">
        <div class="card bg-base-100 shadow-md m-4">
          <div class="card-body">
            <div class="flex flex-wrap gap-2 justify-end">
              <a href="/proximity" class="btn btn-outline btn-sm">
                Proximity Charts
              </a>
              <%= if Radar.enabled?() do %>
                <a href="/radar" class="btn btn-outline btn-sm">
                  Radar
                </a>
                <a href="/radar/debug" class="btn btn-outline btn-sm">
                  Radar Debug
                </a>
              <% end %>
              <a href="/firmware-info" class="btn btn-outline btn-sm">
                Firmware Info
              </a>
              <a href="/sim" class="btn btn-outline btn-sm">
                Open Sim
              </a>
              <a href="/sim3d" class="btn btn-outline btn-sm">
                Open 3D Sim
              </a>
              <a href="/sim3daframe" class="btn btn-outline btn-sm">
                Open 3D Sim Aframe
              </a>
            </div>
          </div>
        </div>

        <%!-- Global Parameters --%>
        <div class="card bg-base-100 shadow-md m-4">
          <div class="card-body">
            <h2 class="card-title">Global Parameters</h2>
            <.live_component
              id="global-params"
              module={OctopusWeb.GlobalParamsComponent}
            />
          </div>
        </div>

        <%!-- Playlists --%>
        <div class="card bg-base-100 shadow-md m-4">
          <div class="card-body">
            <h2 class="card-title">Playlists</h2>
            <div class="card-actions">
              <button
                class="btn btn-primary btn-sm"
                type="button"
                phx-click="playlist-new"
              >
                New Playlist
              </button>
            </div>
            <table class="table table-zebra w-full">
              <tbody>
                <tr :for={{playlist_id, name} <- @playlists}>
                  <td class={if playlist_id == @playlist_selected_id, do: "font-bold"}>
                    <%= if playlist_id == @playlist_selected_id do %>
                      <div class="flex flex-row flex-wrap gap-2 items-center">
                        {name}
                        <div :if={playlist_id == @playlist_selected_id}>
                          <span class={[
                            "badge badge-sm",
                            if(@playlist_status && @playlist_status.status == :running,
                              do: "badge-success",
                              else: "badge-error"
                            )
                          ]}>
                            {if @playlist_status, do: @playlist_status.status}
                          </span>
                        </div>
                      </div>
                    <% else %>
                      {name}
                    <% end %>
                  </td>
                  <td class="flex flex-row flex-wrap gap-2">
                    <button
                      class="btn btn-primary btn-sm"
                      phx-click="playlist-start"
                      phx-value-playlist-id={playlist_id}
                    >
                      ▶
                    </button>
                    <button
                      class={[
                        "btn btn-secondary btn-sm",
                        if(playlist_id != @playlist_selected_id, do: "btn-disabled", else: "")
                      ]}
                      phx-click="playlist-stop"
                      phx-value-playlist-id={playlist_id}
                      disabled={playlist_id != @playlist_selected_id}
                    >
                      ⏹︎
                    </button>
                    <button
                      class={[
                        "btn btn-outline btn-sm",
                        if(playlist_id != @playlist_selected_id, do: "btn-disabled", else: "")
                      ]}
                      phx-click="playlist-prev"
                      phx-value-playlist-id={playlist_id}
                      disabled={playlist_id != @playlist_selected_id}
                    >
                      ⏮
                    </button>
                    <button
                      class={[
                        "btn btn-outline btn-sm",
                        if(playlist_id != @playlist_selected_id, do: "btn-disabled", else: "")
                      ]}
                      phx-click="playlist-next"
                      phx-value-playlist-id={playlist_id}
                      disabled={playlist_id != @playlist_selected_id}
                    >
                      ⏭
                    </button>
                    <.link
                      class="btn btn-accent btn-sm"
                      navigate={~p"/playlist/#{playlist_id}"}
                    >
                      ✎
                    </.link>
                    <button
                      class="btn btn-error btn-sm"
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
                      {app}
                    </td>
                    <td>{timeout}</td>
                    <td class="w-1/2 ">{config |> JSON.encode!()}</td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
        </div>

        <%!-- Running Apps --%>
        <div class="card bg-base-100 shadow-md m-4">
          <div class="card-body">
            <div class="flex items-center justify-between">
              <h2 class="card-title">Running Apps</h2>
              <button
                class="btn btn-outline btn-sm"
                phx-click="toggle_event_scheduler"
                phx-value-val={to_string(!@event_scheduler_started)}
              >
                <%= if @event_scheduler_started do %>
                  Stop
                <% else %>
                  Start
                <% end %>
                Event Scheduler
              </button>
            </div>
            <table class="table table-zebra w-full">
              <tbody>
                <tr
                  :for={
                    %{
                      module: module,
                      app_id: app_id,
                      name: name,
                      selected: selected,
                      output_type: _output_type,
                      masked: masked
                    } <- @running_apps
                  }
                  class={
                    cond do
                      selected -> ""
                      masked -> "opacity-60"
                      true -> ""
                    end
                  }
                >
                  <td class="w-1/2">
                    <div class="flex items-center gap-2">
                      {name}
                      <%= if selected do %>
                        <span class="badge badge-success badge-sm">Active</span>
                      <% end %>
                      <%= if masked do %>
                        <span class="badge badge-neutral badge-sm">Masked</span>
                      <% end %>
                    </div>
                  </td>
                  <td class="flex flex-row gap-2">
                    <button
                      class="btn btn-error btn-sm"
                      phx-click="stop"
                      phx-value-module={module}
                      phx-value-app-id={app_id}
                    >
                      Stop
                    </button>
                    <.link navigate={~p"/app/#{app_id}"} class="btn btn-outline btn-sm">
                      Configure
                    </.link>
                    <button
                      class={[
                        "btn btn-sm",
                        if(selected, do: "btn-success", else: "btn-outline")
                      ]}
                      phx-click="select"
                      phx-value-app-id={app_id}
                    >
                      Show
                    </button>
                    <button
                      class={[
                        "btn btn-sm",
                        if(masked, do: "btn-neutral", else: "btn-outline")
                      ]}
                      phx-click="mask"
                      phx-value-app-id={app_id}
                    >
                      Mask
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

        <div :for={{category, apps} <- @available_apps}>
          <div class="card bg-base-100 shadow-md m-4">
            <div class="card-body">
              <h2 class="card-title">
                {category |> to_string |> String.capitalize()} Apps
              </h2>
              <div class="flex flex-row flex-wrap gap-2">
                <button
                  :for={
                    %{
                      module: module,
                      name: name,
                      icon: icon,
                      compatible: compatible,
                      output_type: output_type
                    } <- apps
                  }
                  class={[
                    "btn btn-sm gap-2",
                    case {output_type, compatible} do
                      {:rgb, true} -> "btn-app-rgb"
                      {:rgb, false} -> "btn-app-rgb btn-disabled"
                      {:grayscale, true} -> "btn-app-grayscale"
                      {:grayscale, false} -> "btn-app-grayscale btn-disabled"
                      {:both, true} -> "btn-app-both"
                      {:both, false} -> "btn-app-both btn-disabled"
                      {_, true} -> "btn-outline"
                      {_, false} -> "btn-outline btn-disabled"
                    end
                  ]}
                  phx-click={if compatible, do: "start", else: nil}
                  phx-value-module={module}
                  disabled={!compatible}
                  title={if !compatible, do: "Incompatible with current installation", else: nil}
                >
                  <%= if icon do %>
                    <div class="w-5 h-5 inline-block rounded-sm overflow-hidden">
                      {raw(icon)}
                    </div>
                  <% end %>
                  {name}
                  <%= if !compatible do %>
                    <span class="text-xs">⚠️</span>
                  <% end %>
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

    case AppSupervisor.start_or_select_app(module) do
      {:ok, app_id} ->
        AppManager.select_app(app_id)
        {:noreply, socket}

      {:error, reason} ->
        message =
          case reason do
            :incompatible -> "App is not compatible with this installation"
            :start_failed -> "Failed to start app"
            :app_not_found -> "App not found"
            _ -> "Could not start app"
          end

        {:noreply, put_flash(socket, :error, message)}
    end
  end

  def handle_event("stop", %{"app-id" => app_id}, socket) do
    AppSupervisor.stop_app(app_id)

    {:noreply, socket}
  end

  def handle_event("select", %{"app-id" => app_id}, socket) do
    AppManager.select_app(app_id)
    {:noreply, socket}
  end

  def handle_event("mask", %{"app-id" => app_id}, socket) do
    AppManager.set_mask_app(app_id)
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

  def handle_event("toggle_event_scheduler", %{"val" => "true"}, socket) do
    KioskModeManager.start()
    {:noreply, socket}
  end

  def handle_event("toggle_event_scheduler", %{"val" => "false"}, socket) do
    KioskModeManager.stop()
    {:noreply, socket}
  end

  def handle_info({:apps, _}, socket) do
    {:noreply, socket |> assign_apps()}
  end

  def handle_info({:app_manager, {:selected_app, _selected_app_id}}, socket) do
    {:noreply, socket |> assign_apps()}
  end

  def handle_info({:app_manager, {:mask_app, _mask_app_id}}, socket) do
    {:noreply, socket |> assign_apps()}
  end

  def handle_info({:app_manager, {:app_lifecycle, _app_id, _event}}, socket) do
    # App lifecycle events (selected/deselected) - no UI action needed
    {:noreply, socket}
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

  def handle_info({:kiosk_mode_manager, :started}, socket) do
    socket = assign(socket, :event_scheduler_started, true)
    {:noreply, socket}
  end

  def handle_info({:kiosk_mode_manager, :stopped}, socket) do
    socket = assign(socket, :event_scheduler_started, false)
    {:noreply, socket}
  end

  def handle_info({:param_updated, _key, _value}, socket) do
    # Update the global params component when parameters change via OSC
    send_update(OctopusWeb.GlobalParamsComponent,
      id: "global-params",
      config: Octopus.Params.Global.config()
    )

    {:noreply, socket}
  end

  defp assign_apps(socket) do
    available_apps =
      for module <- AppSupervisor.available_apps() do
        name = apply(module, :name, [])
        compatible = apply(module, :compatible?, [])

        icon =
          case apply(module, :icon, []) do
            nil -> nil
            canvas -> Canvas.to_svg(canvas, width: "100%", height: "100%")
          end

        category = apply(module, :category, [])
        output_type = apply(module, :output_type, [])

        %{
          module: module,
          name: name,
          icon: icon,
          category: category,
          compatible: compatible,
          output_type: output_type
        }
      end
      |> Enum.group_by(& &1.category)
      |> Enum.sort_by(fn {category, _} ->
        Map.get(%{animation: 0, game: 1, test: 2, misc: 3}, category, 99)
      end)

    selected_app = AppManager.get_selected_app()

    mask_app_id = AppManager.get_mask_app()

    running_apps =
      for {module, app_id} <- AppSupervisor.running_apps() do
        %{
          module: module,
          app_id: app_id,
          name: apply(module, :name, []),
          selected: app_id == selected_app,
          output_type: apply(module, :output_type, []),
          masked: app_id == mask_app_id
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
