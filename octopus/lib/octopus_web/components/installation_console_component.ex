defmodule OctopusWeb.InstallationConsoleComponent do
  @moduledoc false
  use OctopusWeb, :live_component

  import OctopusWeb.ConsoleComponents

  alias Octopus.{AppManager, AppSupervisor, InstallationTransport}
  alias Octopus.Apps.{PixelFun, PixelFun3D, PixieDebug, SparkleMist}

  @app Module.concat(["Octopus", "App"])
  @app_mode_presets Module.concat(["Octopus", "AppModePresets"])

  @debug_apps [PixieDebug]
  @foyer_hidden_apps [PixelFun, SparkleMist]

  def mount(socket) do
    {:ok,
     assign(socket,
       transport: InstallationTransport.get_state(),
       now_ms: System.os_time(:millisecond),
       show_custom_interval: false,
       show_custom_transition: false,
       show_transport_settings: false,
       show_now_playing_panel: false,
       show_all_apps: false,
       show_running_now: false,
       running_apps: [],
       front_app: nil,
       mask_app: nil,
       mask_picker_index: nil,
       mask_eligible_apps: mask_eligible_apps(),
       browse_apps: [],
       browse_app_count: 0,
       console_theme: "light",
       library_sections: nil,
       transform_live: nil,
       editing_pf3d: nil,
       pf3d_app_id: nil,
       show_discard_new_modal: false
     )}
  end

  def update(%{close_pf3d: true}, socket) do
    {:ok, assign(socket, editing_pf3d: nil, pf3d_app_id: nil, show_discard_new_modal: false)}
  end

  def update(assigns, socket) do
    initial_load? = connected?(socket) and is_nil(socket.assigns[:library_sections])

    socket =
      socket
      |> assign(Map.drop(assigns, [:refresh_running, :transport, :refresh_library, :transform_live]))
      |> maybe_assign_transport(assigns)
      |> maybe_assign_transform_live(assigns)
      |> assign_transport_view()
      |> maybe_refresh_library(assigns, initial_load?)
      |> maybe_assign_running(assigns, initial_load?)

    {:ok, socket}
  end

  defp maybe_assign_transform_live(socket, %{transform_live: %{app_id: app_id} = live}) do
    case socket.assigns.transport.now_playing do
      %{app_id: ^app_id} -> assign(socket, transform_live: live)
      _ -> socket
    end
  end

  defp maybe_assign_transform_live(socket, _), do: socket

  def render(assigns) do
    ~H"""
    <div id="installation-console" class="console-root space-y-6" phx-hook=".ConsoleScroll">
      <.console_header />

      <.player_block
        {player_assigns(assigns)}
        show_settings={@show_transport_settings}
        show_now_playing={@show_now_playing_panel}
        now_playing_available={now_playing_panel_available?(assigns)}
        now_playing_dirty={now_playing_panel_dirty?(assigns)}
        front_app={@front_app}
        mask_app={@mask_app}
        target={@myself}
      >
        <:global_params>
          <.live_component id="global-params" module={OctopusWeb.GlobalParamsComponent} layout={:inline} />
        </:global_params>
      </.player_block>

      <section id="mode-library" class="space-y-6 pb-8 scroll-mt-4">
        <.mode_library sections={@library_sections || []} target={@myself} transport={@transport} />
      </section>

      <.running_now_panel
        running_apps={@running_apps}
        front_app={@front_app}
        mask_app={@mask_app}
        expanded={@show_running_now}
        target={@myself}
        dom_id="running-now"
      />
      <.browse_apps
        apps={@browse_apps}
        count={@browse_app_count}
        expanded={@show_all_apps}
        target={@myself}
        dom_id="all-apps"
      />

      <.console_footer />

      <.now_playing_sheet
        :if={@show_now_playing_panel && now_playing_panel_available?(assigns)}
        {now_playing_assigns(assigns)}
        target={@myself}
      />

      <.custom_interval_modal show={@show_custom_interval} target={@myself} />
      <.custom_transition_modal show={@show_custom_transition} target={@myself} />

      <.pf3d_drawer
        :if={@editing_pf3d}
        app_id={@pf3d_app_id}
        mode={@editing_pf3d}
        target={@myself}
      />
      <.discard_new_scene_modal show={@show_discard_new_modal} target={@myself} />

      <script :type={Phoenix.LiveView.ColocatedHook} name=".ConsoleScroll">
      export default {
        mounted() {
          this.handleEvent("scroll_to", ({id}) => {
            document.getElementById(id)?.scrollIntoView({behavior: "smooth", block: "start"})
          })
        }
      }
      </script>
    </div>
    """
  end

  attr :app_id, :string, default: nil
  attr :mode, :any, required: true
  attr :target, :any, required: true

  defp pf3d_drawer(assigns) do
    ~H"""
    <div
      id="pf3d-drawer"
      class="fixed top-10 right-0 bottom-0 z-50 w-full max-w-xl bg-base-100 border-l border-base-300 shadow-2xl overflow-y-auto"
    >
      <div class="sticky top-0 z-10 flex items-center justify-between gap-2 px-4 py-3 bg-base-100 border-b border-base-300">
        <h2 class="text-lg font-semibold">
          {if @mode == :new, do: "Pixel Fun 3D · New scene", else: "Pixel Fun 3D · Scene editor"}
        </h2>
        <button
          type="button"
          class="btn btn-ghost btn-sm btn-square min-h-10 min-w-10"
          phx-click="close_pf3d_editor"
          phx-target={@target}
          aria-label="Close editor"
        >
          <.console_icon_x class="w-5 h-5" />
        </button>
      </div>
      <div class="p-4">
        <.live_component
          :if={@app_id}
          id="pf3d-drawer-editor"
          module={OctopusWeb.PixelFun3DConfigComponent}
          app_id={@app_id}
          app_module={PixelFun3D}
        />
      </div>
    </div>
    """
  end

  attr :show, :boolean, required: true
  attr :target, :any, required: true

  defp now_playing_sheet(assigns) do
    ~H"""
    <div
      id="now-playing-sheet"
      class="fixed inset-x-0 bottom-0 z-50 flex max-h-[min(55vh,28rem)] flex-col border-t border-base-300 bg-base-100 shadow-[0_-10px_40px_rgba(0,0,0,0.15)]"
      role="dialog"
      aria-modal="false"
    >
      <div class="flex shrink-0 items-center justify-between gap-2 border-b border-base-300 px-4 py-3">
        <h2 class="text-lg font-semibold">Now playing</h2>
        <button
          type="button"
          class="btn btn-ghost btn-sm btn-square min-h-10 min-w-10"
          phx-click="close_now_playing_panel"
          phx-target={@target}
          aria-label="Close"
        >
          <.console_icon_x class="w-5 h-5" />
        </button>
      </div>
      <div class="min-h-0 flex-1 overflow-y-auto p-4">
        <.now_playing_card {assigns} id_suffix="sheet" embedded />
      </div>
    </div>
    """
  end

  defp discard_new_scene_modal(assigns) do
    ~H"""
    <div :if={@show} class="modal modal-open" role="dialog">
      <div class="modal-box bg-base-200">
        <h3 class="font-bold text-lg">Unsaved changes</h3>
        <p class="py-2 text-sm opacity-80">
          You have unsaved tweaks on a scratch scene. Discard them or keep editing?
        </p>
        <div class="modal-action mt-0 flex-wrap gap-2">
          <button
            type="button"
            class="btn btn-ghost"
            phx-click="close_discard_new_modal"
            phx-target={@target}
          >
            Keep editing
          </button>
          <button
            type="button"
            class="btn btn-error btn-outline"
            phx-click="discard_new_discard"
            phx-target={@target}
          >
            Discard
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp console_header(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center justify-end gap-3">
      <span class="badge badge-sm bg-[#00d390] text-black border-0 gap-1">
        <span class="w-2 h-2 rounded-full bg-black/30" /> Connected
      </span>
    </div>
    """
  end

  attr :sections, :list, required: true
  attr :transport, :map, required: true
  attr :target, :any, required: true

  defp mode_library(assigns) do
    ~H"""
    <div class="grid gap-6 grid-cols-1 min-[700px]:grid-cols-2 min-[1100px]:grid-cols-3 justify-items-start">
      <div
        :for={section <- @sections}
        class={[
          "card bg-base-200 border border-base-300 min-w-0 w-full",
          section_compact?(section) && "max-w-full",
          !section_compact?(section) && "max-w-[65%]",
          !section_compact?(section) && "min-[700px]:col-span-2 min-[1100px]:col-span-3"
        ]}
      >
        <div class="card-body p-4 gap-3">
          <div class="flex items-center justify-between gap-2">
            <h2 class="text-base font-semibold">{section.title}</h2>
            <div :if={section.app} class="flex items-center gap-1 shrink-0">
              <button
                :if={section.tiles != []}
                type="button"
                class={[
                  "btn btn-sm btn-square min-h-9 min-w-9",
                  section.all_queued? && "btn-primary bg-[#6d7cff] border-[#6d7cff] disabled:opacity-100"
                ]}
                phx-click="queue_add_all"
                phx-value-app={Atom.to_string(section.app)}
                phx-target={@target}
                disabled={section.all_queued?}
                title={if section.all_queued?, do: "All in playlist", else: "Add all to playlist"}
                aria-label={if section.all_queued?, do: "All in playlist", else: "Add all to playlist"}
              >
                <.console_icon_check :if={section.all_queued?} class="w-4 h-4" />
                <.console_icon_plus :if={!section.all_queued?} class="w-4 h-4" />
              </button>
              <button
                type="button"
                class="btn btn-sm btn-square min-h-10 min-w-10"
                phx-click="configure_app"
                phx-value-module={Atom.to_string(section.app)}
                phx-target={@target}
                title={"Configure #{section.title}"}
                aria-label={"Configure #{section.title}"}
              >
                <.console_icon_cog class="w-5 h-5" />
              </button>
            </div>
          </div>

          <div class={["grid gap-3", section_tiles_grid_class(section)]}>
            <.mode_tile
              :for={tile <- section.tiles}
              mode={tile.mode}
              app_module={tile.app}
              live?={tile.live?}
              queued_pos={tile.queued_pos}
              queueable?={Map.get(tile, :queueable?, true)}
              stop_takeover?={tile.stop_takeover?}
              play_now_title={tile.play_now_title}
              target={@target}
            />
            <.soon_tile :for={label <- section.soon} label={label} />
            <button
              :if={section.new_scene?}
              type="button"
              phx-click="new_scene"
              phx-target={@target}
              class="card border-2 border-dashed border-base-content/20 hover:border-primary min-h-[3.5rem] flex items-center justify-center text-center p-2 text-sm opacity-70 hover:opacity-100"
            >
              ＋ New scene
            </button>
          </div>
        </div>
      </div>

      <p class="text-xs opacity-60 px-1 min-[700px]:col-span-2 min-[1100px]:col-span-3">
        Games & test apps launch full-screen and don't join the rotation.
        <button class="link link-primary" phx-click="open_all_apps" phx-target={@target}>
          Show all apps →
        </button>
      </p>
    </div>
    """
  end

  defp section_compact?(section) do
    section_tile_count(section) <= 4
  end

  defp section_tile_count(section) do
    length(section.tiles) +
      length(section.soon) +
      if(section.new_scene?, do: 1, else: 0)
  end

  defp section_tiles_grid_class(section) do
    cond do
      section_compact?(section) ->
        if section_tile_count(section) == 1, do: "grid-cols-1", else: "grid-cols-2"

      true ->
        "grid-cols-2 min-[900px]:grid-cols-3 min-[1280px]:grid-cols-4 min-[1600px]:grid-cols-5"
    end
  end

  defp console_footer(assigns) do
    ~H"""
    <div class="text-center py-4">
      <.link navigate="/playlists" class="text-sm opacity-50 hover:opacity-80 link">
        Advanced: playlist scheduler & raw config →
      </.link>
    </div>
    """
  end

  attr :running_apps, :list, required: true
  attr :front_app, :map, default: nil
  attr :mask_app, :map, default: nil
  attr :expanded, :boolean, required: true
  attr :target, :any, required: true
  attr :class, :string, default: nil
  attr :dom_id, :string, default: "running-now"

  defp running_now_panel(assigns) do
    panel_id = "#{assigns.dom_id}-panel"
    toggle_id = "#{assigns.dom_id}-toggle"

    subtitle =
      cond do
        assigns.front_app && assigns.mask_app -> "Front-App und Mask-App aktiv."
        assigns.front_app -> "Front-App aktiv — keine Mask."
        assigns.mask_app -> "Nur Mask aktiv — keine Front-App."
        true -> "Keine Apps aktiv."
      end

    assigns = assign(assigns, panel_id: panel_id, toggle_id: toggle_id, subtitle: subtitle)

    ~H"""
    <div id={@dom_id} class={["card bg-base-200 border border-base-300", @class]}>
      <div class="card-body p-4 gap-0">
        <button
          type="button"
          id={@toggle_id}
          class="flex w-full items-center justify-between gap-3 text-left min-h-11"
          phx-click="toggle_running_now"
          phx-target={@target}
          aria-expanded={to_string(@expanded)}
          aria-controls={@panel_id}
        >
          <div>
            <h2 class="text-base font-semibold">App-Slots</h2>
            <p class="text-xs opacity-60">{@subtitle}</p>
          </div>
          <span class={["text-lg opacity-50 shrink-0 transition-transform", @expanded && "rotate-180"]}>
            ▾
          </span>
        </button>

        <div :if={@expanded} id={@panel_id} class="pt-4 border-t border-base-300 mt-3">
          <.app_slots front_app={@front_app} mask_app={@mask_app} target={@target} />
        </div>
      </div>
    </div>
    """
  end

  attr :apps, :list, required: true
  attr :count, :integer, required: true
  attr :expanded, :boolean, required: true
  attr :target, :any, required: true
  attr :class, :string, default: nil
  attr :dom_id, :string, default: "all-apps"

  defp browse_apps(assigns) do
    panel_id = "#{assigns.dom_id}-panel"
    toggle_id = "#{assigns.dom_id}-toggle"
    assigns = assign(assigns, panel_id: panel_id, toggle_id: toggle_id)

    ~H"""
    <div id={@dom_id} class={["card bg-base-200 border border-base-300", @class]}>
      <div class="card-body p-4 gap-0">
        <button
          type="button"
          id={@toggle_id}
          class="flex w-full items-center justify-between gap-3 text-left min-h-11"
          phx-click="toggle_all_apps"
          phx-target={@target}
          aria-expanded={to_string(@expanded)}
          aria-controls={@panel_id}
        >
          <div>
            <h2 class="text-base font-semibold">All apps</h2>
            <p class="text-xs opacity-60">
              {@count} legacy, game & test apps — scroll here when you need something off the main library.
            </p>
          </div>
          <span class={["text-lg opacity-50 shrink-0 transition-transform", @expanded && "rotate-180"]}>
            ▾
          </span>
        </button>

        <div :if={@expanded} id={@panel_id} class="space-y-4 pt-4 border-t border-base-300 mt-3">
          <div :for={{category, apps} <- @apps} class="space-y-2">
            <div class="text-xs uppercase opacity-60">{category}</div>
            <div class="flex flex-wrap gap-2">
              <div :for={app <- apps} class="join">
                <button
                  class={["btn btn-sm min-h-11 join-item", !app.compatible && "btn-disabled"]}
                  phx-click="launch_app_as_front"
                  phx-value-module={app.module}
                  phx-target={@target}
                  disabled={!app.compatible}
                  title="Als Front-App starten"
                >
                  {app.name}
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------- events ---

  def handle_event("configure_app", %{"module" => module_string}, socket) do
    module = parse_app_module(module_string)

    case AppSupervisor.start_or_select_app(module) do
      {:ok, app_id} ->
        if module == PixelFun3D do
          {:noreply, assign(socket, editing_pf3d: :existing, pf3d_app_id: app_id)}
        else
          {:noreply, push_navigate(socket, to: ~p"/app/#{app_id}")}
        end

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not open #{app_name(module)} configuration")}
    end
  end

  def handle_event("new_scene", _params, socket) do
    case AppSupervisor.start_or_select_app(PixelFun3D) do
      {:ok, app_id} ->
        InstallationTransport.play_now(PixelFun3D, default_scene_mode_id())

        {:noreply,
         socket
         |> refresh_transport()
         |> assign(editing_pf3d: :new, pf3d_app_id: app_id)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not start #{app_name(PixelFun3D)}")}
    end
  end

  def handle_event("close_pf3d_editor", _params, socket) do
    {:noreply, close_pf3d_editor(socket)}
  end

  def handle_event("close_discard_new_modal", _params, socket) do
    {:noreply, assign(socket, show_discard_new_modal: false)}
  end

  def handle_event("discard_new_discard", _params, socket) do
    InstallationTransport.discard_now_playing_overrides()
    InstallationTransport.resume_rotation_after_takeover()

    {:noreply,
     socket
     |> assign(show_discard_new_modal: false, editing_pf3d: nil, pf3d_app_id: nil)
     |> refresh_transport(refresh_library: true)}
  end

  def handle_event("toggle_play", _params, socket) do
    InstallationTransport.toggle_play()
    {:noreply, refresh_transport(socket)}
  end

  def handle_event("resume_rotation", _params, socket) do
    InstallationTransport.resume_rotation_after_takeover()
    {:noreply, refresh_transport(socket)}
  end

  def handle_event("next", _params, socket) do
    InstallationTransport.next()
    {:noreply, refresh_transport(socket)}
  end

  def handle_event("prev", _params, socket) do
    InstallationTransport.prev()
    {:noreply, refresh_transport(socket)}
  end

  def handle_event("stop_takeover", %{"app" => app, "mode_id" => mode_id}, socket) do
    module = parse_app_module(app)
    transport = socket.assigns.transport

    if takeover_live?(transport, module, mode_id) do
      InstallationTransport.resume_rotation_after_takeover()
      {:noreply, refresh_transport(socket)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("play_now", %{"app" => app, "mode_id" => mode_id}, socket) do
    if blocking_new_scene?(socket) do
      {:noreply, assign(socket, show_discard_new_modal: true)}
    else
      run_play_now(socket, app, mode_id)
    end
  end

  def handle_event("queue_toggle", %{"app" => app, "mode_id" => mode_id}, socket) do
    if blocking_new_scene?(socket) do
      {:noreply, assign(socket, show_discard_new_modal: true)}
    else
      InstallationTransport.queue_toggle(parse_app_module(app), mode_id)
      {:noreply, refresh_transport(socket)}
    end
  end

  def handle_event("queue_add_all", %{"app" => app}, socket) do
    if blocking_new_scene?(socket) do
      {:noreply, assign(socket, show_discard_new_modal: true)}
    else
      InstallationTransport.queue_add_all(parse_app_module(app))
      {:noreply, refresh_transport(socket)}
    end
  end

  def handle_event("queue_remove", %{"index" => index}, socket) do
    InstallationTransport.queue_remove(String.to_integer(index))
    {:noreply, refresh_transport(socket)}
  end

  def handle_event("queue_move", %{"index" => index, "dir" => dir}, socket) do
    InstallationTransport.queue_move(String.to_integer(index), dir)
    {:noreply, refresh_transport(socket)}
  end

  def handle_event("queue_mask_open", %{"index" => index}, socket) do
    idx = String.to_integer(index)

    new_idx =
      if socket.assigns.mask_picker_index == idx do
        nil
      else
        idx
      end

    {:noreply, assign(socket, mask_picker_index: new_idx)}
  end

  def handle_event("queue_set_mask", %{"index" => index} = params, socket) do
    idx = String.to_integer(index)

    mask =
      case params do
        %{"mask_app" => "", "mask_mode_id" => _} ->
          nil

        %{"mask_app" => app, "mask_mode_id" => mode_id} when is_binary(app) and app != "" ->
          %{app: parse_app_module(app), mode_id: mode_id}

        _ ->
          nil
      end

    case InstallationTransport.queue_set_mask(idx, mask) do
      :ok ->
        {:noreply,
         socket
         |> assign(mask_picker_index: nil)
         |> refresh_transport()
         |> assign_running()}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Track not found")}
    end
  end

  def handle_event("set_interval", %{"seconds" => seconds}, socket) do
    InstallationTransport.set_interval(String.to_integer(seconds))
    {:noreply, refresh_transport(socket)}
  end

  def handle_event("open_custom_interval", _params, socket),
    do: {:noreply, assign(socket, show_custom_interval: true)}

  def handle_event("close_custom_interval", _params, socket),
    do: {:noreply, assign(socket, show_custom_interval: false)}

  def handle_event("toggle_transport_settings", _params, socket) do
    {:noreply,
     socket
     |> update(:show_transport_settings, &(!&1))
     |> assign(show_now_playing_panel: false)}
  end

  def handle_event("close_transport_settings", _params, socket),
    do: {:noreply, assign(socket, show_transport_settings: false)}

  def handle_event("toggle_now_playing_panel", _params, socket) do
    {:noreply,
     socket
     |> update(:show_now_playing_panel, &(!&1))
     |> assign(show_transport_settings: false)}
  end

  def handle_event("close_now_playing_panel", _params, socket),
    do: {:noreply, assign(socket, show_now_playing_panel: false)}

  def handle_event("save_custom_interval", %{"value" => value, "unit" => unit}, socket) do
    seconds =
      case parse_number(value) do
        nil ->
          nil

        n ->
          case unit do
            "h" -> trunc(n * 3600)
            "min" -> trunc(n * 60)
            _ -> trunc(n)
          end
      end

    if seconds, do: InstallationTransport.set_interval(seconds)

    {:noreply, socket |> assign(show_custom_interval: false) |> refresh_transport()}
  end

  def handle_event("set_transition_duration", %{"seconds" => seconds}, socket) do
    InstallationTransport.set_transition_duration(parse_number(seconds) || 0)
    {:noreply, refresh_transport(socket)}
  end

  def handle_event("open_custom_transition", _params, socket),
    do: {:noreply, assign(socket, show_custom_transition: true)}

  def handle_event("close_custom_transition", _params, socket),
    do: {:noreply, assign(socket, show_custom_transition: false)}

  def handle_event("save_custom_transition", %{"value" => value}, socket) do
    if seconds = parse_number(value), do: InstallationTransport.set_transition_duration(max(seconds, 0))

    {:noreply, socket |> assign(show_custom_transition: false) |> refresh_transport()}
  end

  def handle_event("toggle_all_apps", _params, socket),
    do: {:noreply, assign(socket, show_all_apps: !socket.assigns.show_all_apps)}

  def handle_event("toggle_running_now", _params, socket),
    do: {:noreply, assign(socket, show_running_now: !socket.assigns.show_running_now)}

  def handle_event("open_all_apps", _params, socket) do
    {:noreply,
     socket
     |> assign(show_all_apps: true)
     |> push_event("scroll_to", %{id: "mode-library"})}
  end

  def handle_event("now_playing_change", params, socket) do
    changes = now_playing_changes(params, socket.assigns.transport.now_playing)

    if map_size(changes) > 0 do
      InstallationTransport.set_tweakables(changes)
    end

    {:noreply, refresh_transport(socket, refresh_library: false)}
  end

  def handle_event("now_playing_choice", %{"key" => key, "index" => index}, socket) do
    np = socket.assigns.transport.now_playing
    key = String.to_existing_atom(key)
    spec = Enum.find(np.tweakables, &(&1.key == key))

    if spec && spec.type == :choice do
      {value, _} = Enum.at(spec.options, String.to_integer(index))

      changes =
        if key == :overflow_mode do
          %{key => value, overflow_auto: false}
        else
          %{key => value}
        end

      InstallationTransport.set_tweakables(changes)
    end

    {:noreply, refresh_transport(socket, refresh_library: false)}
  end

  def handle_event("now_playing_discard", _params, socket) do
    InstallationTransport.discard_now_playing_overrides()
    {:noreply, refresh_transport(socket, refresh_library: false)}
  end

  def handle_event("now_playing_full_editor", _params, socket) do
    case socket.assigns.transport.now_playing do
      %{app: PixelFun3D, app_id: app_id} when is_binary(app_id) ->
        {:noreply, assign(socket, editing_pf3d: :existing, pf3d_app_id: app_id)}

      %{app_id: app_id} when is_binary(app_id) ->
        {:noreply, push_navigate(socket, to: ~p"/app/#{app_id}")}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("select_app", %{"app-id" => app_id}, socket) do
    AppManager.select_app(app_id)
    {:noreply, socket}
  end

  def handle_event("stop_app", %{"app-id" => app_id}, socket) do
    transport = socket.assigns.transport

    if transport.takeover_app_id == app_id do
      InstallationTransport.resume_rotation_after_takeover()
    end

    AppSupervisor.stop_app(app_id)
    {:noreply, socket}
  end

  def handle_event("stop_front_app", _params, socket) do
    transport = socket.assigns.transport
    front_id = socket.assigns[:front_app] && socket.assigns.front_app.app_id

    if front_id && transport.takeover_app_id == front_id do
      InstallationTransport.resume_rotation_after_takeover()
    end

    AppSupervisor.stop_front_app()
    {:noreply, socket}
  end

  def handle_event("launch_app", %{"module" => module_string}, socket) do
    InstallationTransport.launch_app(parse_app_module(module_string))
    {:noreply, refresh_transport(socket) |> assign_running()}
  end

  def handle_event("launch_app_as_front", %{"module" => module_string}, socket) do
    module = parse_app_module(module_string)

    case AppSupervisor.start_as_front_app(module) do
      {:ok, _app_id} ->
        {:noreply, assign_running(socket)}

      {:error, :incompatible} ->
        {:noreply, put_flash(socket, :error, "#{app_name(module)} ist nicht kompatibel mit dieser Installation")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Konnte #{app_name(module)} nicht starten")}
    end
  end

  defp refresh_transport(socket, opts \\ []) do
    socket =
      socket
      |> assign(transport: InstallationTransport.get_state())
      |> assign_transport_view()

    if Keyword.get(opts, :refresh_library, false) do
      assign_library(socket)
    else
      refresh_library_transport(socket)
    end
  end

  # Closing a brand-new scene with unsaved edits prompts to save/discard;
  # otherwise the scratch takeover is dropped and rotation resumes.
  defp close_pf3d_editor(%{assigns: %{editing_pf3d: :new}} = socket) do
    if now_playing_dirty?(socket) do
      assign(socket, show_discard_new_modal: true)
    else
      InstallationTransport.discard_now_playing_overrides()
      InstallationTransport.resume_rotation_after_takeover()

      socket
      |> assign(editing_pf3d: nil, pf3d_app_id: nil)
      |> refresh_transport(refresh_library: true)
    end
  end

  defp close_pf3d_editor(socket) do
    assign(socket, editing_pf3d: nil, pf3d_app_id: nil)
  end

  defp now_playing_dirty?(socket) do
    match?(%{dirty: true}, socket.assigns.transport.now_playing)
  end

  defp blocking_new_scene?(socket) do
    socket.assigns.editing_pf3d == :new and now_playing_dirty?(socket)
  end

  defp run_play_now(socket, app, mode_id) do
    module = parse_app_module(app)

    message =
      case InstallationTransport.play_now(module, mode_id) do
        :ok ->
          nil

        {:error, :incompatible} ->
          "#{app_name(module)} is not compatible with this installation"

        {:error, _} ->
          "Could not play #{app_name(module)} · #{mode_id}"
      end

    socket = refresh_transport(socket)
    socket = if message, do: put_flash(socket, :error, message), else: socket

    {:noreply, socket}
  end

  defp default_scene_mode_id, do: "pixelfun3d:classic_ripple"

  defp parse_app_module(str) when is_binary(str) do
    cond do
      String.starts_with?(str, "Elixir.") ->
        String.to_existing_atom(str)

      String.contains?(str, ".") ->
        str |> String.split(".") |> Enum.map(&String.to_existing_atom/1) |> Module.concat()

      true ->
        Module.concat(Octopus.Apps, String.to_existing_atom(str))
    end
  end

  defp parse_app_module(module) when is_atom(module), do: module

  # -------------------------------------------------------------- helpers ---

  defp assign_transport_view(socket) do
    transport = socket.assigns.transport
    now = socket.assigns.now_ms
    count = length(transport.queue)
    rotating? = count >= 1 and not transport.rotation_paused
    playing = transport.playing and not transport.rotation_paused
    interval_seconds = trunc(transport.cycle_interval_seconds || 300)
    transition_seconds = transport.transition_duration_seconds || 1.0

    remaining_ms =
      cond do
        !rotating? -> nil
        !playing and is_integer(transport.paused_remaining_ms) -> transport.paused_remaining_ms
        !playing -> nil
        is_integer(transport.next_change_at_ms) -> max(transport.next_change_at_ms - now, 0)
        true -> nil
      end

    interval_ms = interval_seconds * 1000

    countdown_percent =
      case remaining_ms do
        nil -> 0
        ms when interval_ms > 0 -> round(ms / interval_ms * 100)
        _ -> 0
      end

    live = transport.live

    live_label =
      cond do
        live ->
          "#{live.app_name} · #{live.mode_name}"

        transport.rotation_paused && transport.takeover_app_name ->
          transport.takeover_app_name

        true ->
          "—"
      end
    takeover? = transport.rotation_paused

    transport_mode =
      cond do
        transport.rotation_paused ->
          :takeover

        count == 0 && is_nil(live) ->
          :idle

        count >= 1 && !transport.playing ->
          :paused

        count >= 1 && transport.playing ->
          :rotating

        true ->
          :idle
      end

    next_entry =
      if rotating? and count >= 2 do
        next_index = rem(transport.cycle_index + 1, count)
        Enum.at(transport.queue, next_index)
      end

    subtitle =
      cond do
        transport_mode == :takeover ->
          name = transport.takeover_app_name || live_label
          "#{name} on wall — queue waiting."

        transport_mode == :paused ->
          "Rotation paused."

        transport_mode == :rotating && count == 1 ->
          "Restarts every #{interval_label(interval_seconds)}."

        transport_mode == :rotating && next_entry ->
          next_item = rem(transport.cycle_index + 1, count) + 1
          "Next: #{next_entry.app_name} · #{next_entry.mode_name} · item #{next_item} of #{count}"

        transport_mode == :idle ->
          "Nothing queued — pick a mode."

        true ->
          ""
      end

    live_index = if live, do: Enum.find_index(transport.queue, &entry_match?(&1, live)), else: nil

    up_next_index =
      if rotating? and count >= 2 do
        rem(transport.cycle_index + 1, count)
      end

    socket
    |> assign(
      rotating?: rotating?,
      playing: playing,
      takeover?: takeover?,
      transport_mode: transport_mode,
      live_label: live_label,
      live?: not is_nil(live),
      subtitle: subtitle,
      countdown_percent: countdown_percent,
      elapsed_percent: 100 - countdown_percent,
      countdown_label: format_mmss(remaining_ms),
      interval_seconds: interval_seconds,
      interval_label: interval_label(interval_seconds),
      interval_custom?: not Enum.any?(interval_presets(), fn {_l, s} -> s == interval_seconds end),
      transition_seconds: transition_seconds * 1.0,
      transition_label: transition_label(transition_seconds),
      transition_custom?:
        not Enum.any?(transition_presets(), fn {_l, s} -> s == transition_seconds * 1.0 end),
      queue_count: count,
      live_index: live_index,
      up_next_index: up_next_index,
      holding_label: live_label,
      show_now_playing_panel:
        socket.assigns[:show_now_playing_panel] && not is_nil(live) && not is_nil(transport.now_playing)
    )
  end

  defp maybe_assign_transport(socket, %{transport: transport}), do: assign(socket, :transport, transport)
  defp maybe_assign_transport(socket, _assigns), do: socket

  defp maybe_refresh_library(socket, %{refresh_library: true}, _initial_load?), do: assign_library(socket)
  defp maybe_refresh_library(socket, %{transport: _transport}, false), do: refresh_library_transport(socket)
  defp maybe_refresh_library(socket, _assigns, true), do: assign_library(socket)
  defp maybe_refresh_library(socket, _assigns, false), do: socket

  defp maybe_assign_running(socket, assigns, initial_load?) do
    if initial_load? or Map.get(assigns, :refresh_running, false) do
      assign_running(socket)
    else
      socket
    end
  end

  defp refresh_library_transport(%{assigns: %{library_sections: sections}} = socket)
       when is_list(sections) do
    transport = socket.assigns.transport

    sections =
      Enum.map(sections, fn section ->
        modes = Enum.map(section.tiles, & &1.mode)
        tiles = tile_list(section.app, modes, transport)
        %{section | tiles: tiles, all_queued?: section_all_queued?(tiles)}
      end)

    assign(socket, library_sections: sections)
  end

  defp refresh_library_transport(socket), do: socket

  defp assign_library(socket) do
    transport = socket.assigns.transport

    pixel_section = library_section(PixelFun3D, "Pixel Fun 3D", transport, new_scene?: true)

    debug_sections =
      if apply(PixieDebug, :compatible?, []) do
        [library_section(PixieDebug, "Pixie Debug", transport)]
      else
        []
      end

    more_sections =
      for app <- persistable_apps(), app not in [PixelFun3D | @foyer_hidden_apps] do
        library_section(app, app_name(app), transport)
      end

    assign(socket, library_sections: [pixel_section | debug_sections ++ more_sections])
  end

  defp library_section(app, title, transport, opts \\ []) do
    tiles = tile_list(app, app_list_modes(app), transport)

    %{
      title: title,
      app: app,
      new_scene?: Keyword.get(opts, :new_scene?, false),
      soon: [],
      tiles: tiles,
      all_queued?: section_all_queued?(tiles)
    }
  end

  defp section_all_queued?(tiles), do: tiles != [] and Enum.all?(tiles, & &1.queued_pos)

  defp tile_list(app, modes, transport, opts \\ []) do
    queueable? = Keyword.get(opts, :queueable?, true)
    rotating_active? = length(transport.queue) >= 2 and not transport.rotation_paused

    Enum.map(modes, fn mode ->
      queued_pos = queue_position(transport.queue, app, mode.id, 1)

      %{
        app: app,
        mode: mode,
        live?: live?(transport, app, mode.id),
        queued_pos: queued_pos,
        queueable?: queueable?,
        stop_takeover?: takeover_live?(transport, app, mode.id),
        play_now_title: play_now_title(queued_pos, rotating_active?)
      }
    end)
  end

  defp play_now_title(queued_pos, _rotating_active?) when not is_nil(queued_pos), do: "Jump to this mode"
  defp play_now_title(_queued_pos, true), do: "Preview — pauses rotation"
  defp play_now_title(_queued_pos, _rotating_active?), do: "Show on the wall"

  defp assign_running(socket) do
    front_id = AppManager.get_selected_app()
    mask_id = AppManager.get_mask_app()

    running =
      for {module, app_id} <- AppSupervisor.running_apps() do
        %{
          module: module,
          app_id: app_id,
          name: app_name(module),
          selected: app_id == front_id,
          masked: app_id == mask_id,
          mask_eligible?: AppManager.supports_grayscale_module?(module)
        }
      end

    front_app = Enum.find(running, & &1.selected)
    mask_app = Enum.find(running, & &1.masked)

    browse_apps =
      AppSupervisor.available_apps()
      |> Enum.reject(&(&1 in @debug_apps))
      |> Enum.map(fn module ->
        %{
          module: module,
          name: app_name(module),
          compatible: apply(module, :compatible?, []),
          category: app_category(module),
          mask_eligible?: AppManager.supports_grayscale_module?(module)
        }
      end)

    browse =
      browse_apps
      |> Enum.group_by(& &1.category)
      |> Enum.sort_by(fn {cat, _} -> category_order(cat) end)

    socket
    |> assign(
      running_apps: running,
      front_app: front_app,
      mask_app: mask_app,
      browse_apps: browse,
      browse_app_count: length(browse_apps)
    )
  end

  defp app_name(module), do: apply(@app, :name, [module])
  defp app_list_modes(module), do: apply(@app, :list_modes, [module])
  defp app_category(module), do: apply(@app, :category, [module])
  defp persistable_apps, do: apply(@app_mode_presets, :persistable_apps, [])

  defp category_order(:animation), do: 0
  defp category_order(:interactive), do: 1
  defp category_order(:game), do: 2
  defp category_order(:test), do: 3
  defp category_order(_), do: 4

  defp player_assigns(assigns) do
    Map.merge(
      Map.take(assigns, [
        :playing,
        :rotating?,
        :takeover?,
        :transport_mode,
        :live_label,
        :live?,
        :subtitle,
        :countdown_percent,
        :countdown_label,
        :interval_seconds,
        :interval_custom?,
        :interval_label,
        :transition_seconds,
        :transition_custom?,
        :transition_label
      ]),
      queue_assigns(assigns)
    )
  end

  defp now_playing_panel_available?(assigns) do
    assigns.live? && assigns.transport.now_playing != nil
  end

  defp now_playing_panel_dirty?(assigns) do
    case assigns.transport.now_playing do
      %{dirty: true} -> true
      _ -> false
    end
  end

  defp now_playing_assigns(assigns) do
    np = assigns.transport.now_playing

    np =
      if np && assigns[:transform_live] do
        Map.put(np, :transform_live, assigns.transform_live)
      else
        np
      end

    %{
      now_playing: np,
      live: assigns.transport.live,
      rotating?: assigns.rotating?,
      playing: assigns.playing,
      countdown_percent: assigns.countdown_percent,
      countdown_label: assigns.countdown_label
    }
  end

  defp now_playing_changes(_params, nil), do: %{}

  defp now_playing_changes(params, now_playing) do
    keys = now_playing_target_keys(params, now_playing)

    params
    |> Map.drop(["_target"])
    |> Enum.filter(fn {key, _} -> tweakable_param_key?(key, keys) end)
    |> Map.new(fn {key, value} -> {String.to_existing_atom(key), value} end)
  end

  defp now_playing_target_keys(%{"_target" => target}, _now_playing) when is_list(target) do
    Enum.flat_map(target, &now_playing_schema_key/1)
  end

  defp now_playing_target_keys(%{"_target" => target}, _now_playing) when is_binary(target) do
    now_playing_schema_key(target)
  end

  defp now_playing_target_keys(params, now_playing) do
    tweakable_keys = Enum.map(now_playing.tweakables, & &1.key)

    params
    |> Map.drop(["_target"])
    |> Map.keys()
    |> Enum.flat_map(&now_playing_schema_key/1)
    |> Enum.filter(&(&1 in tweakable_keys))
  end

  defp now_playing_schema_key(key) do
    [String.to_existing_atom(key)]
  rescue
    ArgumentError -> []
  end

  defp tweakable_param_key?(key, keys) do
    case now_playing_schema_key(key) do
      [atom] -> atom in keys
      _ -> false
    end
  end

  defp queue_assigns(assigns) do
    %{
      queue: assigns.transport.queue,
      count: assigns.queue_count,
      interval_label: assigns.interval_label,
      transition_label: assigns.transition_label,
      live_index: assigns.live_index,
      up_next_index: assigns.up_next_index,
      elapsed_percent: assigns.elapsed_percent,
      countdown_label: assigns.countdown_label,
      holding_label: assigns.holding_label,
      mask_picker_index: assigns.mask_picker_index,
      mask_eligible_apps: assigns.mask_eligible_apps
    }
  end

  defp mask_eligible_apps do
    AppSupervisor.available_apps()
    |> Enum.filter(fn app ->
      AppManager.supports_grayscale_module?(app) and apply(app, :compatible?, [])
    end)
    |> Enum.map(fn app ->
      %{
        module: app,
        name: app_name(app),
        modes: app_list_modes(app)
      }
    end)
    |> Enum.sort_by(& &1.name)
  end

  defp entry_match?(%{app: app, mode_id: mode_id}, %{app: app, mode_id: mode_id}), do: true
  defp entry_match?(_, _), do: false

  defp parse_number(value) when is_binary(value) do
    case Float.parse(value) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp parse_number(_), do: nil
end
