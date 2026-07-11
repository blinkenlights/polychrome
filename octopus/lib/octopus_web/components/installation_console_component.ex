defmodule OctopusWeb.InstallationConsoleComponent do
  @moduledoc false
  use OctopusWeb, :live_component

  import OctopusWeb.ConsoleComponents

  alias Octopus.{AppManager, AppSupervisor, InstallationTransport}
  alias Octopus.Apps.{PixelFun, PixieDebug}
  alias Octopus.Apps.{PixelFun, PixieDebug}

  @app Module.concat(["Octopus", "App"])
  @app_mode_presets Module.concat(["Octopus", "AppModePresets"])

  @debug_apps [PixieDebug]

  def mount(socket) do
    {:ok,
     assign(socket,
       transport: InstallationTransport.get_state(),
       now_ms: System.os_time(:millisecond),
       active_tab: "queue",
       show_custom_interval: false,
       show_all_apps: false,
       show_running_now: false,
       show_now_playing_save_modal: false,
       now_playing_save_name: "",
       show_now_playing_rename_modal: false,
       now_playing_rename_name: "",
       show_now_playing_delete_modal: false,
       running_apps: [],
       browse_apps: [],
       browse_app_count: 0,
       console_theme: "light",
       library_sections: nil
     )}
  end

  def update(assigns, socket) do
    initial_load? = connected?(socket) and is_nil(socket.assigns[:library_sections])

    socket =
      socket
      |> assign(Map.drop(assigns, [:refresh_running, :transport, :refresh_library]))
      |> maybe_assign_transport(assigns)
      |> assign_transport_view()
      |> maybe_refresh_library(assigns, initial_load?)
      |> maybe_assign_running(assigns, initial_load?)

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="console-root space-y-6">
      <.console_header />

      <%!-- Main console (wide) --%>
      <div class="hidden min-[700px]:block space-y-6 pb-8">
        <div class="grid gap-6 min-[900px]:grid-cols-[minmax(0,2fr)_minmax(0,1fr)] min-[900px]:items-start">
          <.transport_bar {transport_bar_assigns(assigns)} target={@myself} />
          <.queue_card {queue_assigns(assigns)} target={@myself} />
        </div>

        <div class="grid gap-6 min-[900px]:grid-cols-[minmax(0,2fr)_minmax(0,1fr)] min-[900px]:items-start">
          <.mode_library sections={@library_sections || []} target={@myself} transport={@transport} />
          <div class="space-y-6">
            <.global_params_card />
            <.now_playing_card {now_playing_assigns(assigns)} id_suffix="desktop" target={@myself} />
          </div>
        </div>
      </div>

      <%!-- Mobile --%>
      <div class="min-[700px]:hidden space-y-4">
        <.mini_transport {mini_transport_assigns(assigns)} target={@myself} />
        <.global_params_card mobile />

        <div role="tablist" class="tabs tabs-boxed">
          <button
            :for={{id, label} <- [{"queue", "Playlist"}, {"library", "Library"}]}
            role="tab"
            class={["tab min-h-11", @active_tab == id && "tab-active"]}
            phx-click="select_tab"
            phx-value-tab={id}
            phx-target={@myself}
          >
            {label}
          </button>
        </div>

        <div class={@active_tab != "queue" && "hidden"}>
          <.queue_card {queue_assigns(assigns)} target={@myself} />
          <.now_playing_card {now_playing_assigns(assigns)} id_suffix="mobile" target={@myself} />
          <.running_now_panel
            running_apps={@running_apps}
            expanded={@show_running_now}
            target={@myself}
            class="mt-4"
          />
        </div>
        <div class={@active_tab != "library" && "hidden"}>
          <.mode_library sections={@library_sections || []} target={@myself} transport={@transport} compact />
          <.browse_apps
            apps={@browse_apps}
            count={@browse_app_count}
            expanded={@show_all_apps}
            target={@myself}
            class="mt-4"
          />
        </div>
      </div>

      <div class="hidden min-[700px]:block space-y-4">
        <.running_now_panel
          running_apps={@running_apps}
          expanded={@show_running_now}
          target={@myself}
          dom_id="running-now-desktop"
        />
        <.browse_apps
          apps={@browse_apps}
          count={@browse_app_count}
          expanded={@show_all_apps}
          target={@myself}
          dom_id="all-apps-desktop"
        />
      </div>

      <.console_footer />

      <.custom_interval_modal show={@show_custom_interval} target={@myself} />
      <.now_playing_save_modal
        show={@show_now_playing_save_modal}
        name={@now_playing_save_name}
        preset_label={now_playing_preset_label(@transport)}
        target={@myself}
      />
      <.now_playing_rename_modal
        show={@show_now_playing_rename_modal}
        name={@now_playing_rename_name}
        preset_label={now_playing_preset_label(@transport)}
        target={@myself}
      />
      <.now_playing_delete_modal
        show={@show_now_playing_delete_modal}
        preset_name={now_playing_preset_name(@transport)}
        preset_label={now_playing_preset_label(@transport)}
        target={@myself}
      />
    </div>
    """
  end

  attr :mobile, :boolean, default: false

  defp global_params_card(assigns) do
    ~H"""
    <div class="card bg-base-200 border border-base-300 shadow-sm">
      <div class="card-body p-4">
        <.live_component
          id={if(@mobile, do: "global-params-mobile", else: "global-params-desktop")}
          module={OctopusWeb.GlobalParamsComponent}
        />
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
  attr :compact, :boolean, default: false

  defp mode_library(assigns) do
    ~H"""
    <div class="space-y-6">
      <div :for={section <- @sections} class="card bg-base-200 border border-base-300">
        <div class="card-body p-4 gap-3">
          <div class="flex items-center justify-between gap-2">
            <h2 class="text-base font-semibold">{section.title}</h2>
            <button
              :if={section.app}
              type="button"
              class="text-sm link link-primary"
              phx-click="configure_app"
              phx-value-module={Atom.to_string(section.app)}
              phx-target={@target}
            >
              Configure {section.title} →
            </button>
          </div>

          <div class={[
            "grid gap-3",
            if(@compact,
              do: "grid-cols-1",
              else: "grid-cols-2 min-[900px]:grid-cols-3 min-[1280px]:grid-cols-4 min-[1600px]:grid-cols-5"
            )
          ]}>
            <.mode_tile
              :for={tile <- section.tiles}
              mode={tile.mode}
              app_name={section.title}
              app_module={tile.app}
              live?={tile.live?}
              queued_pos={tile.queued_pos}
              queueable?={Map.get(tile, :queueable?, true)}
              stop_takeover?={tile.stop_takeover?}
              play_now_title={tile.play_now_title}
              target={@target}
            />
            <.soon_tile :for={label <- section.soon} label={label} />
            <.link
              :if={section.new_scene_path}
              navigate={section.new_scene_path}
              class="card border-2 border-dashed border-base-content/20 hover:border-primary min-h-[7rem] flex items-center justify-center text-center p-3 text-sm opacity-70 hover:opacity-100"
            >
              ＋ New scene
            </.link>
          </div>
        </div>
      </div>

      <p class="text-xs opacity-60 px-1">
        Games & test apps launch full-screen and don't join the rotation.
        <button class="link link-primary" phx-click="open_all_apps" phx-target={@target}>
          Show all apps →
        </button>
      </p>
    </div>
    """
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
  attr :expanded, :boolean, required: true
  attr :target, :any, required: true
  attr :class, :string, default: nil
  attr :dom_id, :string, default: "running-now"

  defp running_now_panel(assigns) do
    panel_id = "#{assigns.dom_id}-panel"
    toggle_id = "#{assigns.dom_id}-toggle"
    count = length(assigns.running_apps)

    subtitle =
      case count do
        0 -> "No apps running — Show, Mask & Stop for games and test apps."
        1 -> "1 app running — Only one app is Active at a time."
        n -> "#{n} apps running — Only one app is Active at a time."
      end

    assigns =
      assigns
      |> assign(panel_id: panel_id, toggle_id: toggle_id, subtitle: subtitle)

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
            <h2 class="text-base font-semibold">Running now</h2>
            <p class="text-xs opacity-60">{@subtitle}</p>
          </div>
          <span class={["text-lg opacity-50 shrink-0 transition-transform", @expanded && "rotate-180"]}>
            ▾
          </span>
        </button>

        <div :if={@expanded} id={@panel_id} class="pt-4 border-t border-base-300 mt-3">
          <.running_now_rows running_apps={@running_apps} target={@target} />
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
              <button
                :for={app <- apps}
                class={["btn btn-sm min-h-11", !app.compatible && "btn-disabled"]}
                phx-click="launch_app"
                phx-value-module={app.module}
                phx-target={@target}
                disabled={!app.compatible}
              >
                {app.name}
              </button>
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
        {:noreply, push_navigate(socket, to: ~p"/app/#{app_id}")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not open #{app_name(module)} configuration")}
    end
  end

  def handle_event("select_tab", %{"tab" => tab}, socket), do: {:noreply, assign(socket, active_tab: tab)}

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

  def handle_event("queue_toggle", %{"app" => app, "mode_id" => mode_id}, socket) do
    InstallationTransport.queue_toggle(parse_app_module(app), mode_id)
    {:noreply, refresh_transport(socket)}
  end

  def handle_event("queue_remove", %{"index" => index}, socket) do
    InstallationTransport.queue_remove(String.to_integer(index))
    {:noreply, refresh_transport(socket)}
  end

  def handle_event("queue_move", %{"index" => index, "dir" => dir}, socket) do
    InstallationTransport.queue_move(String.to_integer(index), dir)
    {:noreply, refresh_transport(socket)}
  end

  def handle_event("set_interval", %{"seconds" => seconds}, socket) do
    InstallationTransport.set_interval(String.to_integer(seconds))
    {:noreply, refresh_transport(socket)}
  end

  def handle_event("open_custom_interval", _params, socket),
    do: {:noreply, assign(socket, show_custom_interval: true)}

  def handle_event("close_custom_interval", _params, socket),
    do: {:noreply, assign(socket, show_custom_interval: false)}

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

  def handle_event("toggle_all_apps", _params, socket),
    do: {:noreply, assign(socket, show_all_apps: !socket.assigns.show_all_apps)}

  def handle_event("toggle_running_now", _params, socket),
    do: {:noreply, assign(socket, show_running_now: !socket.assigns.show_running_now)}

  def handle_event("open_all_apps", _params, socket) do
    {:noreply, assign(socket, show_all_apps: true, active_tab: "library")}
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
      InstallationTransport.set_tweakable(key, value)
    end

    {:noreply, refresh_transport(socket, refresh_library: false)}
  end

  def handle_event("now_playing_discard", _params, socket) do
    InstallationTransport.discard_now_playing_overrides()
    {:noreply, refresh_transport(socket, refresh_library: false)}
  end

  def handle_event("open_now_playing_save_modal", _params, socket),
    do: {:noreply, assign(socket, show_now_playing_save_modal: true, now_playing_save_name: "")}

  def handle_event("close_now_playing_save_modal", _params, socket),
    do: {:noreply, assign(socket, show_now_playing_save_modal: false, now_playing_save_name: "")}

  def handle_event("now_playing_save_name_change", %{"name" => name}, socket),
    do: {:noreply, assign(socket, now_playing_save_name: name)}

  def handle_event("now_playing_save_as_new", %{"name" => name}, socket) do
    label = preset_label(socket)

    case InstallationTransport.save_now_playing_as_new(name) do
      :ok ->
        {:noreply,
         socket
         |> assign(show_now_playing_save_modal: false, now_playing_save_name: "")
         |> refresh_transport()
         |> assign_library()}

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "Could not save #{label}")
         |> assign(now_playing_save_name: name)}
    end
  end

  def handle_event("now_playing_overwrite", _params, socket) do
    label = preset_label(socket)

    case InstallationTransport.overwrite_now_playing_mode() do
      :ok ->
        {:noreply, refresh_transport(socket) |> assign_library()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not overwrite #{label}")}
    end
  end

  def handle_event("open_now_playing_rename_modal", _params, socket) do
    name = socket.assigns.transport.now_playing && socket.assigns.transport.now_playing.preset_name || ""

    {:noreply,
     assign(socket, show_now_playing_rename_modal: true, now_playing_rename_name: name)}
  end

  def handle_event("close_now_playing_rename_modal", _params, socket),
    do: {:noreply, assign(socket, show_now_playing_rename_modal: false, now_playing_rename_name: "")}

  def handle_event("now_playing_rename_change", %{"name" => name}, socket),
    do: {:noreply, assign(socket, now_playing_rename_name: name)}

  def handle_event("now_playing_rename", %{"name" => name}, socket) do
    label = preset_label(socket)
    name = String.trim(name)

    if name == "" do
      {:noreply, put_flash(socket, :error, "Enter a #{label} name")}
    else
      case InstallationTransport.rename_now_playing_preset(name) do
        :ok ->
          {:noreply,
           socket
           |> assign(show_now_playing_rename_modal: false, now_playing_rename_name: "")
           |> refresh_transport()
           |> assign_library()}

        {:error, _} ->
          {:noreply,
           socket
           |> put_flash(:error, "Could not rename #{label}")
           |> assign(now_playing_rename_name: name)}
      end
    end
  end

  def handle_event("open_now_playing_delete_modal", _params, socket),
    do: {:noreply, assign(socket, show_now_playing_delete_modal: true)}

  def handle_event("close_now_playing_delete_modal", _params, socket),
    do: {:noreply, assign(socket, show_now_playing_delete_modal: false)}

  def handle_event("now_playing_delete", _params, socket) do
    label = preset_label(socket)

    case InstallationTransport.archive_now_playing_mode() do
      :ok ->
        {:noreply,
         socket
         |> assign(show_now_playing_delete_modal: false)
         |> refresh_transport()
         |> assign_library()}

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "Could not delete #{label}")
         |> assign(show_now_playing_delete_modal: false)}
    end
  end

  def handle_event("now_playing_full_editor", _params, socket) do
    case socket.assigns.transport.now_playing do
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

  def handle_event("mask_app", %{"app-id" => app_id}, socket) do
    AppManager.set_mask_app(app_id)
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

  def handle_event("launch_app", %{"module" => module_string}, socket) do
    InstallationTransport.launch_app(parse_app_module(module_string))
    {:noreply, refresh_transport(socket) |> assign_running()}
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
    rotating? = count >= 2 and not transport.rotation_paused
    playing = transport.playing and not transport.rotation_paused
    interval_seconds = trunc(transport.cycle_interval_seconds || 300)

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
    live_label = if live, do: "#{live.app_name} · #{live.mode_name}", else: "—"
    takeover? = transport.rotation_paused

    transport_mode =
      cond do
        transport.rotation_paused ->
          :takeover

        count == 0 && is_nil(live) ->
          :idle

        count >= 2 && !transport.playing ->
          :paused

        count >= 2 && transport.playing ->
          :rotating

        true ->
          :hold
      end

    next_entry =
      if rotating? do
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

        transport_mode == :rotating && next_entry ->
          "Next: #{next_entry.app_name} · #{next_entry.mode_name} · item #{transport.cycle_index + 2} of #{count}"

        transport_mode == :idle ->
          "Nothing queued — pick a mode."

        transport_mode == :hold ->
          "Single mode — add another to rotate."

        true ->
          "Holding this mode — add more to rotate."
      end

    live_index = if live, do: Enum.find_index(transport.queue, &entry_match?(&1, live)), else: nil

    up_next_index =
      if rotating? do
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
      queue_count: count,
      live_index: live_index,
      up_next_index: up_next_index,
      holding_label: live_label
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
        %{section | tiles: tile_list(section.app, modes, transport)}
      end)

    assign(socket, library_sections: sections)
  end

  defp refresh_library_transport(socket), do: socket

  defp assign_library(socket) do
    transport = socket.assigns.transport
    pixel_fun_app_id = AppSupervisor.find_running_app(PixelFun) |> elem_or_nil()

    pixel_section = %{
      title: "Pixel Fun",
      app: PixelFun,
      new_scene_path: if(pixel_fun_app_id, do: ~p"/app/#{pixel_fun_app_id}", else: nil),
      soon: [],
      tiles: tile_list(PixelFun, app_list_modes(PixelFun), transport)
    }

    more_sections =
      for app <- persistable_apps(), app != PixelFun do
        %{
          title: app_name(app),
          app: app,
          new_scene_path: nil,
          soon: [],
          tiles: tile_list(app, app_list_modes(app), transport)
        }
      end

    assign(socket, library_sections: [pixel_section | more_sections])
  end

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
    selected = AppManager.get_selected_app()
    mask = AppManager.get_mask_app()

    running =
      for {module, app_id} <- AppSupervisor.running_apps() do
        %{
          module: module,
          app_id: app_id,
          name: app_name(module),
          selected: app_id == selected,
          masked: app_id == mask
        }
      end

    browse_apps =
      AppSupervisor.available_apps()
      |> Enum.reject(&(&1 in @debug_apps))
      |> Enum.map(fn module ->
        %{
          module: module,
          name: app_name(module),
          compatible: apply(module, :compatible?, []),
          category: app_category(module)
        }
      end)

    browse =
      browse_apps
      |> Enum.group_by(& &1.category)
      |> Enum.sort_by(fn {cat, _} -> category_order(cat) end)

    socket
    |> assign(running_apps: running, browse_apps: browse, browse_app_count: length(browse_apps))
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

  defp transport_bar_assigns(assigns) do
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
      :interval_custom?
    ])
  end

  defp mini_transport_assigns(assigns) do
    Map.take(assigns, [
      :playing,
      :rotating?,
      :takeover?,
      :transport_mode,
      :live_label,
      :live?,
      :subtitle,
      :countdown_percent,
      :countdown_label
    ])
  end

  defp now_playing_assigns(assigns) do
    %{
      now_playing: assigns.transport.now_playing,
      live: assigns.transport.live,
      rotating?: assigns.rotating?,
      playing: assigns.playing,
      countdown_percent: assigns.countdown_percent,
      countdown_label: assigns.countdown_label
    }
  end

  defp now_playing_preset_label(%{now_playing: %{preset_label: label}}) when is_binary(label), do: label
  defp now_playing_preset_label(_), do: "preset"

  defp now_playing_preset_name(%{now_playing: %{preset_name: name}}) when is_binary(name), do: name
  defp now_playing_preset_name(_), do: ""

  defp preset_label(socket) do
    case socket.assigns.transport.now_playing do
      %{preset_label: label} when is_binary(label) -> label
      _ -> "preset"
    end
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
      live_index: assigns.live_index,
      up_next_index: assigns.up_next_index,
      elapsed_percent: assigns.elapsed_percent,
      countdown_label: assigns.countdown_label,
      holding_label: assigns.holding_label
    }
  end

  defp entry_match?(%{app: app, mode_id: mode_id}, %{app: app, mode_id: mode_id}), do: true
  defp entry_match?(_, _), do: false

  defp elem_or_nil({:ok, id}), do: id
  defp elem_or_nil(_), do: nil

  defp parse_number(value) when is_binary(value) do
    case Float.parse(value) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp parse_number(_), do: nil
end
