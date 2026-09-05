defmodule OctopusWeb.ManagerLive do
  use OctopusWeb, :live_view

  alias Octopus.InstallationTransport
  alias Octopus.Params.Global
  alias OctopusWeb.PixelsLive

  def mount(_params, _session, socket) do
    if connected?(socket) do
      InstallationTransport.subscribe()
      Octopus.AppSupervisor.subscribe()
      Octopus.AppManager.subscribe()
      Global.subscribe()
      :timer.send_interval(1000, :console_tick)
    end

    socket =
      socket
      |> setup_preview(Application.fetch_env!(:octopus, :show_sim_preview))
      |> assign(
        now_ms: System.os_time(:millisecond),
        console_theme: "light",
        sim_layout: "top"
      )

    {:ok, socket}
  end

  def handle_event("set_console_theme", %{"theme" => theme}, socket)
      when theme in ["dark", "light"] do
    {:noreply, assign(socket, console_theme: theme)}
  end

  def handle_event("toggle_console_theme", _params, socket) do
    theme = if socket.assigns.console_theme == "dark", do: "light", else: "dark"

    {:noreply,
     socket
     |> assign(console_theme: theme)
     |> push_event("store-console-theme", %{theme: theme})}
  end

  def handle_event("set_sim_layout", %{"layout" => layout}, socket)
      when layout in ["top", "left"] do
    {:noreply, assign(socket, sim_layout: layout)}
  end

  def handle_event("toggle_sim_layout", _params, socket) do
    layout = if socket.assigns.sim_layout == "left", do: "top", else: "left"

    {:noreply,
     socket
     |> assign(sim_layout: layout)
     |> push_event("store-console-sim-layout", %{layout: layout})}
  end

  defp setup_preview(socket, true) do
    Octopus.Mixer.subscribe()

    socket
    |> assign(show_sim_preview: true)
  end

  defp setup_preview(socket, false) do
    assign(socket, show_sim_preview: false)
  end

  def render(assigns) do
    ~H"""
    <div
      id="console-page"
      phx-hook="ConsoleTheme"
      data-sim-preview={@show_sim_preview}
      data-sim-layout={@sim_layout}
      class={[
        "w-full",
        @show_sim_preview &&
          "min-[700px]:fixed min-[700px]:inset-x-0 min-[700px]:bottom-0 min-[700px]:top-10 min-[700px]:z-20 min-[700px]:flex min-[700px]:flex-col min-[700px]:overflow-hidden",
        @show_sim_preview && @sim_layout == "left" && "sim-layout-left",
        !@show_sim_preview && "relative"
      ]}
    >
      <%= if @show_sim_preview do %>
        <%!-- phx-update="ignore" prevents LiveView from re-patching this div on every
             console_tick, which would reset the JS-set inline height and cause snap-back.
             Default height lives in the <style> rule below; JS inline style overrides it. --%>
        <div
          id="sim-preview"
          phx-update="ignore"
          class="shrink-0 z-30 relative w-full bg-black border-b border-base-300 overflow-hidden"
        >
          {live_render(@socket, PixelsLive, id: "main", session: %{"embedded" => true})}
          <%!-- Vertical drag handle for left layout — shown/hidden via CSS --%>
          <div
            id="sim-resize-handle-vert"
            phx-hook="SimResize"
            data-direction="horizontal"
            title="Drag to resize"
            class="absolute inset-y-0 right-0 w-1.5 cursor-col-resize touch-none select-none z-50 bg-transparent hover:bg-primary/40 active:bg-primary/60 transition-colors"
          />
        </div>
        <%!-- Horizontal drag handle for top layout — shown/hidden via CSS --%>
        <div
          id="sim-resize-handle"
          phx-hook="SimResize"
          data-direction="vertical"
          title="Drag to resize"
          class="group max-[699px]:hidden shrink-0 h-2 cursor-row-resize touch-none select-none z-40 bg-base-300 hover:bg-primary/40 active:bg-primary/60 transition-colors flex items-center justify-center"
        >
          <span class="w-8 h-0.5 rounded-full bg-base-content/25 group-hover:bg-primary/70 transition-colors" />
        </div>
      <% end %>

      <div
        data-theme={@console_theme}
        class={[
          "min-h-0",
          @show_sim_preview &&
            "min-[700px]:flex-1 min-[700px]:overflow-y-auto min-[700px]:overscroll-y-contain",
          @console_theme == "dark" && "bg-[#0f1318] text-base-content",
          @console_theme == "light" && "bg-base-200 text-base-content"
        ]}
      >
        <style>
          .console-root{font-family:"IBM Plex Sans",ui-sans-serif,system-ui,sans-serif}
          .console-mono{font-family:"IBM Plex Mono",ui-monospace,SFMono-Regular,monospace}
          #sim-preview{height:25dvh}
          #sim-resize-handle{display:none}
          #sim-resize-handle-vert{display:none}
          @media (min-width:700px){
            #sim-preview{height:42dvh}
            #sim-resize-handle{display:flex}
            #console-page.sim-layout-left{flex-direction:row}
            #console-page.sim-layout-left #sim-preview{
              width:min(42dvw,28rem);
              max-height:none;
              height:100%;
              border-bottom:none;
              border-right:1px solid color-mix(in oklch,currentColor 15%,transparent)
            }
            #console-page.sim-layout-left .sim-embedded-root{height:100%;min-height:0}
            #console-page.sim-layout-left .sim-embedded-canvas{flex:1;min-height:0}
            #console-page.sim-layout-left #sim-resize-handle{display:none}
            #console-page.sim-layout-left #sim-resize-handle-vert{display:block}
          }
        </style>
        <div class="w-full px-4 sm:px-6 lg:px-8 py-6">
          <.live_component
            id="installation-console"
            module={OctopusWeb.InstallationConsoleComponent}
            now_ms={@now_ms}
            console_theme={@console_theme}
          />
        </div>
      </div>
    </div>
    """
  end

  def handle_info(:console_tick, socket) do
    {:noreply, assign(socket, now_ms: System.os_time(:millisecond))}
  end

  def handle_info({:installation_transport, transport}, socket) do
    send_update(OctopusWeb.InstallationConsoleComponent,
      id: "installation-console",
      transport: transport
    )

    {:noreply, socket}
  end

  def handle_info({:apps, {:transform_live, app_id, values}}, socket) do
    send_update(OctopusWeb.InstallationConsoleComponent,
      id: "installation-console",
      transform_live: Map.put(values, :app_id, app_id)
    )

    {:noreply, socket}
  end

  def handle_info({:apps, _}, socket) do
    send_update(OctopusWeb.InstallationConsoleComponent,
      id: "installation-console",
      refresh_running: true
    )

    {:noreply, socket}
  end

  def handle_info({:app_manager, _}, socket) do
    send_update(OctopusWeb.InstallationConsoleComponent,
      id: "installation-console",
      refresh_running: true
    )

    {:noreply, socket}
  end

  # The params component is rendered once, nested inside
  # InstallationConsoleComponent's player block (see its :global_params slot).
  def handle_info({:param_updated, key, value}, socket)
      when key in [:speed, :brightness, :auto_brightness] do
    send_update(OctopusWeb.GlobalParamsComponent,
      id: "global-params",
      param_key: key,
      param_value: value
    )

    {:noreply, socket}
  end

  def handle_info({:mixer, _}, socket), do: {:noreply, socket}
end
