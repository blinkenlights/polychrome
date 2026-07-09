defmodule OctopusWeb.ManagerLive do
  use OctopusWeb, :live_view

  import OctopusWeb.CoreComponents

  alias Octopus.Installation
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

    installation_label =
      Application.get_env(:octopus, :installation_label, "Foyer wall")

    panel_hint =
      "#{Installation.num_panels()} panels · #{Installation.width()}×#{Installation.height()} px"

    socket =
      socket
      |> setup_preview(Application.fetch_env!(:octopus, :show_sim_preview))
      |> assign(
        installation_label: installation_label,
        panel_hint: panel_hint,
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
    <.flash_group flash={@flash} />
    <div
      id="console-page"
      phx-hook="ConsoleTheme"
      data-sim-preview={@show_sim_preview}
      data-sim-layout={@sim_layout}
      class={[
        "w-full",
        @show_sim_preview && "fixed inset-0 z-20 flex flex-col overflow-hidden",
        @show_sim_preview && @sim_layout == "left" && "sim-layout-left",
        !@show_sim_preview && "relative"
      ]}
    >
      <div class="fixed top-3 right-3 z-50 flex gap-2">
        <%= if @show_sim_preview do %>
          <button
            id="sim-layout-toggle"
            type="button"
            class="hidden min-[700px]:inline-flex btn btn-sm btn-circle shadow-lg border border-base-300 bg-base-100"
            phx-click="toggle_sim_layout"
            aria-label={if @sim_layout == "left", do: "Sim oben", else: "Sim links"}
            title={if @sim_layout == "left", do: "Sim oben", else: "Sim links"}
          >
            {if @sim_layout == "left", do: "↑", else: "←"}
          </button>
        <% end %>
        <button
          type="button"
          class="btn btn-sm btn-circle shadow-lg border border-base-300 bg-base-100"
          phx-click="toggle_console_theme"
          aria-label={if @console_theme == "dark", do: "Light mode", else: "Dark mode"}
          title={if @console_theme == "dark", do: "Light mode", else: "Dark mode"}
        >
          {if @console_theme == "dark", do: "☀", else: "☾"}
        </button>
      </div>

      <%= if @show_sim_preview do %>
        <div
          id="sim-preview"
          class={[
            "shrink-0 z-30 w-full max-h-[42dvh] bg-black border-b border-base-300 overflow-hidden",
            @sim_layout == "left" && "sim-layout-left"
          ]}
        >
          {live_render(@socket, PixelsLive, id: "main", session: %{"embedded" => true})}
        </div>
      <% end %>

      <div
        data-theme={@console_theme}
        class={[
          "min-h-0",
          @show_sim_preview && "flex-1 overflow-y-auto overscroll-y-contain",
          @console_theme == "dark" && "bg-[#0f1318] text-base-content",
          @console_theme == "light" && "bg-base-200 text-base-content"
        ]}
      >
        <style>
          .console-root{font-family:"IBM Plex Sans",ui-sans-serif,system-ui,sans-serif}
          .console-mono{font-family:"IBM Plex Mono",ui-monospace,SFMono-Regular,monospace}
          @media (min-width:700px){
            #console-page.sim-layout-left{flex-direction:row}
            #sim-preview.sim-layout-left{
              width:min(42dvw,28rem);
              max-height:none;
              height:100%;
              border-bottom:none;
              border-right:1px solid color-mix(in oklch,currentColor 15%,transparent)
            }
            #sim-preview.sim-layout-left .sim-embedded-root{height:100%;min-height:0}
            #sim-preview.sim-layout-left .sim-embedded-canvas{max-height:none;flex:1;min-height:0}
          }
        </style>
        <div class="w-full px-4 sm:px-6 lg:px-8 py-6">
          <.live_component
            id="installation-console"
            module={OctopusWeb.InstallationConsoleComponent}
            installation_label={@installation_label}
            panel_hint={@panel_hint}
            now_ms={@now_ms}
            console_theme={@console_theme}
          />
        </div>
      </div>
    </div>
    """
  end

  def handle_info(:console_tick, socket) do
    send_update(OctopusWeb.InstallationConsoleComponent,
      id: "installation-console",
      now_ms: System.os_time(:millisecond)
    )

    {:noreply, assign(socket, now_ms: System.os_time(:millisecond))}
  end

  def handle_info({:installation_transport, transport}, socket) do
    send_update(OctopusWeb.InstallationConsoleComponent,
      id: "installation-console",
      transport: transport
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

  def handle_info({:param_updated, key, value}, socket)
      when key in [:speed, :brightness, :auto_brightness] do
    for id <- ["global-params-desktop", "global-params-mobile"] do
      send_update(OctopusWeb.GlobalParamsComponent,
        id: id,
        param_key: key,
        param_value: value
      )
    end

    {:noreply, socket}
  end

  def handle_info({:mixer, _}, socket), do: {:noreply, socket}
end
