defmodule OctopusWeb.AppLive do
  alias Octopus.Layout.Mildenberg
  use OctopusWeb, :live_view

  alias Octopus.AppSupervisor
  alias Octopus.Mixer
  alias OctopusWeb.PixelsComponent

  import OctopusWeb.PixelsComponent, only: [pixels: 1]

  def mount(%{"id" => app_id}, _session, socket) do
    if connected?(socket) do
      Mixer.subscribe()
      AppSupervisor.subscribe()
    end

    {_pid, module} = AppSupervisor.lookup_app(app_id)
    name = apply(module, :name, [])

    socket =
      socket
      |> assign(
        app_id: app_id,
        module: module,
        name: name,
        pixel_layout: Mildenberg.layout()
      )
      |> PixelsComponent.setup()

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="container mx-auto flex flex-col items-center">
      <h1 class="text-2xl font-semibold leading-loose"><%= @name %></h1>
      <.live_component
        id={"app-config-#{@app_id}"}
        module={OctopusWeb.AppConfigComponent}
        app_id={@app_id}
        app_module={@module}
      />
    </div>
    """
  end

  def handle_info({:apps, {:config_updated, app_id, config}}, socket) do
    if app_id == socket.assigns.app_id do
      send_update(OctopusWeb.AppConfigComponent, id: "app-config-#{app_id}", config: config)
    end

    {:noreply, socket}
  end

  def handle_info(_, socket) do
    {:noreply, socket}
  end
end
