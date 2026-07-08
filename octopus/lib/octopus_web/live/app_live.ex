defmodule OctopusWeb.AppLive do
  use OctopusWeb, :live_view

  alias Octopus.AppSupervisor
  alias Octopus.Apps.{PixelFun, Wood}

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
            name: apply(module, :name, []),
            app_config: AppSupervisor.config(app_id)
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
      <div class={[
        "card bg-base-100 shadow-lg mx-auto",
        @module == PixelFun && "max-w-6xl",
        @module != PixelFun && "max-w-2xl"
      ]}>
        <div class="card-body">
          <h1 class="card-title text-3xl justify-center">{@name}</h1>
          <%= cond do %>
            <% @module == PixelFun -> %>
              <.live_component
                id={"app-config-#{@app_id}"}
                module={OctopusWeb.PixelFunConfigComponent}
                app_id={@app_id}
                app_module={@module}
                config={@app_config}
              />
            <% @module == Wood -> %>
              <.live_component
                id={"app-config-#{@app_id}"}
                module={OctopusWeb.WoodConfigComponent}
                app_id={@app_id}
                app_module={@module}
                config={@app_config}
              />
            <% true -> %>
              <.live_component
                id={"app-config-#{@app_id}"}
                module={OctopusWeb.AppConfigComponent}
                app_id={@app_id}
                app_module={@module}
              />
          <% end %>
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
      socket = assign(socket, app_config: config)

      send_update(config_component_module(socket.assigns.module),
        id: "app-config-#{app_id}",
        app_id: app_id,
        app_module: socket.assigns.module,
        config: config
      )

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_info(_, socket) do
    {:noreply, socket}
  end

  defp config_component_module(PixelFun), do: OctopusWeb.PixelFunConfigComponent
  defp config_component_module(Wood), do: OctopusWeb.WoodConfigComponent
  defp config_component_module(_), do: OctopusWeb.AppConfigComponent

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
