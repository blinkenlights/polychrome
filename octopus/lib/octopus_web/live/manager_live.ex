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
      |> assign(installation_label: installation_label, panel_hint: panel_hint, now_ms: System.os_time(:millisecond))

    {:ok, socket}
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
    <div class="w-full">
      <%= if @show_sim_preview do %>
        <div class="flex w-full h-full justify-center bg-black">
          {live_render(@socket, PixelsLive, id: "main")}
        </div>
      <% end %>

      <div data-theme="dark" class="bg-[#0f1318] min-h-screen text-base-content">
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
