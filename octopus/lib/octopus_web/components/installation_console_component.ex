defmodule OctopusWeb.InstallationConsoleComponent do
  @moduledoc false
  use OctopusWeb, :live_component

  import OctopusWeb.ConsoleComponents

  alias Octopus.{App, AppManager, AppSupervisor, InstallationTransport}
  alias Octopus.Apps.{Collective, DoomFire, PixelFun}

  @wired_apps [PixelFun, Collective, DoomFire]
  @pixel_fun_preview 6

  def mount(socket) do
    {:ok,
     assign(socket,
       transport: InstallationTransport.get_state(),
       now_ms: System.os_time(:millisecond),
       active_tab: "queue",
       show_custom_interval: false,
       show_all_pixel_fun: false,
       running_apps: [],
       browse_apps: []
     )}
  end

  def update(assigns, socket) do
    socket =
      socket
      |> assign(Map.drop(assigns, [:refresh_running]))
      |> assign_transport_view()
      |> assign_library()
      |> assign_running()

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="console-root space-y-6">
      <.console_header installation_label={@installation_label} panel_hint={@panel_hint} />

      <%!-- Desktop / narrow --%>
      <div class="hidden min-[700px]:block space-y-6">
        <.transport_bar {transport_bar_assigns(assigns)} target={@myself} />

        <div class="grid gap-6 min-[1100px]:grid-cols-[1.2fr_1fr] min-[1100px]:items-start">
          <div class="min-[1100px]:col-start-1 space-y-6 order-2 min-[1100px]:order-none">
            <.mode_library sections={@library_sections} target={@myself} transport={@transport} show_all_pixel_fun={@show_all_pixel_fun} />
          </div>
          <div class="min-[1100px]:col-start-2 space-y-6 order-1 min-[1100px]:order-none">
            <.queue_card {queue_assigns(assigns)} target={@myself} />
            <.running_now_strip running_apps={@running_apps} target={@myself} />
            <.global_settings />
          </div>
        </div>
      </div>

      <%!-- Mobile --%>
      <div class="min-[700px]:hidden space-y-4">
        <.mini_transport {mini_transport_assigns(assigns)} target={@myself} />

        <div role="tablist" class="tabs tabs-boxed">
          <button
            :for={{id, label} <- [{"queue", "Queue"}, {"library", "Library"}, {"apps", "Apps"}]}
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
        </div>
        <div class={@active_tab != "library" && "hidden"}>
          <.mode_library sections={@library_sections} target={@myself} transport={@transport} compact show_all_pixel_fun={@show_all_pixel_fun} />
        </div>
        <div class={@active_tab != "apps" && "hidden"}>
          <.running_now_strip running_apps={@running_apps} target={@myself} />
          <.browse_apps apps={@browse_apps} target={@myself} />
        </div>
      </div>

      <.console_footer />

      <.custom_interval_modal show={@show_custom_interval} target={@myself} />
    </div>
    """
  end

  attr :installation_label, :string, required: true
  attr :panel_hint, :string, required: true

  defp console_header(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center justify-between gap-3">
      <div>
        <h1 class="text-xl font-semibold">{@installation_label}</h1>
        <p class="text-sm opacity-60">{@panel_hint}</p>
      </div>
      <div class="flex items-center gap-2">
        <span class="badge badge-sm bg-[#00d390] text-black border-0 gap-1">
          <span class="w-2 h-2 rounded-full bg-black/30" /> Connected
        </span>
        <div class="dropdown dropdown-end">
          <div tabindex="0" role="button" class="btn btn-ghost btn-sm">Sim ▾</div>
          <ul tabindex="0" class="dropdown-content menu bg-base-200 rounded-box z-30 w-44 p-2 shadow">
            <li><a href="/sim">Open Sim</a></li>
            <li><a href="/sim3d">Open 3D Sim</a></li>
            <li><a href="/proximity">Proximity</a></li>
            <li><a href="/firmware-info">Firmware Info</a></li>
          </ul>
        </div>
      </div>
    </div>
    """
  end

  attr :sections, :list, required: true
  attr :transport, :map, required: true
  attr :target, :any, required: true
  attr :show_all_pixel_fun, :boolean, default: false
  attr :compact, :boolean, default: false

  defp mode_library(assigns) do
    ~H"""
    <div class="space-y-6">
      <div :for={section <- @sections} class="card bg-base-200 border border-base-300">
        <div class="card-body p-4 gap-3">
          <div class="flex items-center justify-between gap-2">
            <h2 class="text-base font-semibold">{section.title}</h2>
            <.link :if={section.configure_path} navigate={section.configure_path} class="text-sm link link-primary">
              Configure {section.title} →
            </.link>
          </div>

          <div class={[
            "grid gap-3",
            if(@compact, do: "grid-cols-1", else: "grid-cols-1 min-[700px]:grid-cols-2")
          ]}>
            <.mode_tile
              :for={tile <- section.tiles}
              mode={tile.mode}
              app_name={section.title}
              app_module={tile.app}
              live?={tile.live?}
              queued_pos={tile.queued_pos}
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

          <button
            :if={section.show_more_count && section.show_more_count > 0 && !@show_all_pixel_fun}
            class="btn btn-ghost btn-sm self-start"
            phx-click="show_more_pixel_fun"
            phx-target={@target}
          >
            Show {section.show_more_count} more
          </button>
        </div>
      </div>

      <p class="text-xs opacity-60 px-1">
        Games & test apps launch full-screen and don't join the rotation.
        <button class="link link-primary" phx-click="select_tab" phx-value-tab="apps" phx-target={@target}>
          Browse all apps →
        </button>
      </p>
    </div>
    """
  end

  defp global_settings(assigns) do
    ~H"""
    <div tabindex="0" class="collapse collapse-arrow bg-base-200 border border-base-300">
      <input type="checkbox" />
      <div class="collapse-title font-semibold">Global settings</div>
      <div class="collapse-content">
        <.live_component id="global-params-console" module={OctopusWeb.GlobalParamsComponent} />
      </div>
    </div>
    """
  end

  defp console_footer(assigns) do
    ~H"""
    <div class="text-center py-4">
      <.link navigate={~p"/playlists"} class="text-sm opacity-50 hover:opacity-80 link">
        Advanced: playlist scheduler & raw config →
      </.link>
    </div>
    """
  end

  attr :apps, :list, required: true
  attr :target, :any, required: true

  defp browse_apps(assigns) do
    ~H"""
    <div class="card bg-base-200 border border-base-300 mt-4">
      <div class="card-body p-4 gap-3">
        <h2 class="text-base font-semibold">Launch app</h2>
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
    """
  end

  # ---------------------------------------------------------------- events ---

  def handle_event("select_tab", %{"tab" => tab}, socket), do: {:noreply, assign(socket, active_tab: tab)}

  def handle_event("toggle_play", _params, socket) do
    InstallationTransport.toggle_play()
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

  def handle_event("play_now", %{"app" => app, "mode_id" => mode_id}, socket) do
    InstallationTransport.play_now(parse_app_module(app), mode_id)
    {:noreply, refresh_transport(socket)}
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

  def handle_event("show_more_pixel_fun", _params, socket),
    do: {:noreply, assign(socket, show_all_pixel_fun: true) |> assign_library()}

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

  defp refresh_transport(socket) do
    socket
    |> assign(transport: InstallationTransport.get_state())
    |> assign_transport_view()
    |> assign_library()
  end

  defp parse_app_module(str) when is_binary(str) do
    cond do
      String.starts_with?(str, "Elixir.") ->
        String.to_existing_atom(str)

      String.contains?(str, ".") ->
        str |> String.split(".") |> Enum.map(&String.to_existing_atom/1) |> Module.concat()

      true ->
        String.to_existing_atom(str)
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

    next_entry =
      if rotating? do
        next_index = rem(transport.cycle_index + 1, count)
        Enum.at(transport.queue, next_index)
      end

    subtitle =
      cond do
        transport.rotation_paused && transport.takeover_app_name ->
          "#{transport.takeover_app_name} is on the wall — queue resumes when it stops."

        !playing && rotating? ->
          "Paused — holding current mode."

        rotating? && next_entry ->
          "Next: #{next_entry.app_name} · #{next_entry.mode_name} · item #{transport.cycle_index + 2} of #{count}"

        count == 0 ->
          "Nothing queued — pick a mode to show."

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

  defp assign_library(socket) do
    transport = socket.assigns.transport
    pixel_fun_app_id = AppSupervisor.find_running_app(PixelFun) |> elem_or_nil()

    pixel_modes =
      PixelFun.list_modes()
      |> then(fn modes ->
        if socket.assigns.show_all_pixel_fun, do: modes, else: Enum.take(modes, @pixel_fun_preview)
      end)

    show_more = max(length(PixelFun.list_modes()) - @pixel_fun_preview, 0)

    pixel_section = %{
      title: "Pixel Fun",
      configure_path: if(pixel_fun_app_id, do: ~p"/app/#{pixel_fun_app_id}", else: nil),
      new_scene_path: if(pixel_fun_app_id, do: ~p"/app/#{pixel_fun_app_id}", else: nil),
      show_more_count: if(socket.assigns.show_all_pixel_fun, do: 0, else: show_more),
      soon: [],
      tiles: tile_list(PixelFun, pixel_modes, transport)
    }

    more_sections =
      for app <- [Collective, DoomFire] do
        %{
          title: App.name(app),
          configure_path: nil,
          new_scene_path: nil,
          show_more_count: 0,
          soon: [],
          tiles: tile_list(app, App.list_modes(app), transport)
        }
      end

    stub_sections = stub_app_sections(transport)

    assign(socket, library_sections: [pixel_section | more_sections] ++ stub_sections)
  end

  defp stub_app_sections(_transport) do
    wired = MapSet.new(@wired_apps)

    AppSupervisor.available_apps()
    |> Enum.filter(&(App.rotation_eligible?(&1) and &1 not in wired and App.category(&1) == :animation))
    |> Enum.group_by(&App.name/1)
    |> Enum.map(fn {name, _modules} ->
      %{
        title: name,
        configure_path: nil,
        new_scene_path: nil,
        show_more_count: 0,
        soon: [name],
        tiles: []
      }
    end)
  end

  defp tile_list(app, modes, transport) do
    Enum.map(modes, fn mode ->
      %{
        app: app,
        mode: mode,
        live?: live?(transport, app, mode.id),
        queued_pos: queue_position(transport.queue, app, mode.id, 1)
      }
    end)
  end

  defp assign_running(socket) do
    selected = AppManager.get_selected_app()
    mask = AppManager.get_mask_app()

    running =
      for {module, app_id} <- AppSupervisor.running_apps() do
        %{
          module: module,
          app_id: app_id,
          name: App.name(module),
          selected: app_id == selected,
          masked: app_id == mask
        }
      end

    browse =
      AppSupervisor.available_apps()
      |> Enum.map(fn module ->
        %{
          module: module,
          name: App.name(module),
          compatible: apply(module, :compatible?, []),
          category: App.category(module)
        }
      end)
      |> Enum.group_by(& &1.category)
      |> Enum.sort_by(fn {cat, _} -> category_order(cat) end)

    socket
    |> assign(running_apps: running, browse_apps: browse)
  end

  defp category_order(:animation), do: 0
  defp category_order(:interactive), do: 1
  defp category_order(:game), do: 2
  defp category_order(:test), do: 3
  defp category_order(_), do: 4

  defp transport_bar_assigns(assigns) do
    Map.take(assigns, [
      :playing,
      :rotating?,
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
      :live_label,
      :live?,
      :subtitle,
      :countdown_percent,
      :countdown_label
    ])
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
