defmodule OctopusWeb.AppLive do
  use OctopusWeb, :live_view

  alias Octopus.AppSupervisor

  def mount(%{"id" => app_id}, _session, socket) do
    case AppSupervisor.lookup_app(app_id) do
      {_pid, module} ->
        if connected?(socket) do
          AppSupervisor.subscribe()
        end

        socket =
          socket
          |> assign(
            app_id: app_id,
            module: module,
            name: apply(module, :name, [])
          )
          |> assign_playlist_config()

        {:ok, socket}

      nil ->
        {:ok,
         socket
         |> put_flash(:error, "App #{app_id} is not running")
         |> redirect(to: ~p"/")}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="container mx-auto p-4">
      <div class="card bg-base-100 shadow-lg max-w-2xl mx-auto">
        <div class="card-body">
          <h1 class="card-title text-3xl justify-center">{@name}</h1>
          <.live_component
            id={"app-config-#{@app_id}"}
            module={OctopusWeb.AppConfigComponent}
            app_id={@app_id}
            app_module={@module}
          />
        </div>
      </div>

      <div class="card bg-base-100 shadow-lg max-w-2xl mx-auto mt-4">
        <div class="card-body">
          <h2 class="card-title">Config for Playlist</h2>
          <div class="mockup-code">
            <pre><code>{@playlist_config}</code></pre>
          </div>
        </div>
      </div>
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

  defp assign_playlist_config(socket) do
    config = %{
      app: Module.split(socket.assigns.module) |> List.last(),
      config: AppSupervisor.config(socket.assigns.app_id),
      timeout: 60_000
    }

    socket =
      socket
      |> assign(playlist_config: JSON.encode!(config))

    socket
  end
end
