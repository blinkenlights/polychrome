defmodule OctopusWeb.ManagerLive do
  use OctopusWeb, :live_view

  alias Octopus.Installation
  alias Octopus.InstallationTransport
  alias OctopusWeb.PixelsLive

  def mount(_params, _session, socket) do
    if connected?(socket) do
      InstallationTransport.subscribe()
      Octopus.AppSupervisor.subscribe()
      Octopus.AppManager.subscribe()
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
        console_theme: "light"
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
    <div id="console-page" phx-hook="ConsoleTheme" class="w-full relative">
      <button
        type="button"
        class="fixed top-3 right-3 z-50 btn btn-sm btn-circle shadow-lg border border-base-300 bg-base-100"
        phx-click="toggle_console_theme"
        aria-label={if @console_theme == "dark", do: "Light mode", else: "Dark mode"}
        title={if @console_theme == "dark", do: "Light mode", else: "Dark mode"}
      >
        {if @console_theme == "dark", do: "☀", else: "☾"}
      </button>

      <%= if @show_sim_preview do %>
        <div class="w-full bg-black shrink-0 border-b border-base-300">
          {live_render(@socket, PixelsLive, id: "main", session: %{"embedded" => true})}
        </div>
      <% end %>

      <div
        data-theme={@console_theme}
        class={[
          "min-h-0",
          @console_theme == "dark" && "bg-[#0f1318] text-base-content",
          @console_theme == "light" && "bg-base-200 text-base-content"
        ]}
      >
        <style>
          .console-root{font-family:"IBM Plex Sans",ui-sans-serif,system-ui,sans-serif}
          .console-mono{font-family:"IBM Plex Mono",ui-monospace,SFMono-Regular,monospace}
        </style>
        <div class="container mx-auto max-w-6xl px-4 py-6">
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
  def handle_info({:mixer, _}, socket), do: {:noreply, socket}
end
