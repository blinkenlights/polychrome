defmodule OctopusWeb.ManagerLive do
  use OctopusWeb, :live_view
  use OctopusWeb.PixelsComponent

  alias Octopus.{Mixer, AppSupervisor}
  alias Octopus.Protobuf.InputEvent
  alias OctopusWeb.PixelsComponent

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Mixer.subscribe()
      AppSupervisor.subscribe()
    end

    socket = PixelsComponent.mount(socket)

    {:ok, socket |> assign_apps()}
  end

  def render(assigns) do
    ~H"""
    <div class="w-full" phx-window-keydown="keydown-event">
      <div class="flex w-full h-full justify-center bg-black">
        <.pixels id="pixels" pixel_layout={@pixel_layout} />
      </div>

      <div class="container mx-auto">
        <div class="flex flex-col">
          <div class="border rounded m-2 p-2">
            <table class="w-full table-auto border-separate text-left">
              <thead>
                <tr>
                  <th class="text-left">App</th>
                  <th>Actions</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={{module, %{name: name}} <- @available_apps}>
                  <td><%= name %></td>
                  <td>
                    <button
                      class="border py-1 px-2 rounded"
                      phx-click="start"
                      phx-value-module={module}
                    >
                      Start
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <div class="border rounded m-2 p-2">
            <table class="w-full table-auto border-separate text-left">
              <thead>
                <tr>
                  <th class="text-left">App</th>
                  <th class="text-left">App ID</th>
                  <th>Actions</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={
                  {app_id, %{module: module, name: name, selected: selected}} <- @running_apps
                }>
                  <td><%= name %></td>
                  <td><%= app_id %></td>
                  <td>
                    <button
                      class="border py-1 px-2 rounded"
                      phx-click="stop"
                      phx-value-module={module}
                      phx-value-app-id={app_id}
                    >
                      Stop
                    </button>

                    <button
                      :if={!selected}
                      class="border py-1 px-2 rounded"
                      phx-click="select"
                      phx-value-module={module}
                      phx-value-app-id={app_id}
                    >
                      Select
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def handle_event("start", %{"module" => module_string}, socket) do
    case Map.get(socket.assigns.available_apps, module_string) do
      %{module: module} ->
        {:ok, _} = AppSupervisor.start_app(module)
        {:noreply, socket}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("stop", %{"app-id" => app_id}, socket) do
    if Map.has_key?(socket.assigns.running_apps, app_id) do
      AppSupervisor.stop_app(app_id)
    end

    {:noreply, socket}
  end

  def handle_event("select", %{"app-id" => app_id}, socket) do
    if Map.has_key?(socket.assigns.running_apps, app_id) do
      Mixer.select_app(app_id)
    end

    {:noreply, socket}
  end

  def handle_event("keydown-event", %{"key" => key}, socket)
      when key in ~w(0 1 2 3 4 5 6 7 8 9) do
    %InputEvent{type: :BUTTON, value: String.to_integer(key)}
    |> Mixer.handle_input()

    {:noreply, socket}
  end

  def handle_event("keydown-event", %{"key" => _other_key}, socket) do
    {:noreply, socket}
  end

  def handle_info({:mixer, {:selected_app, selected_app_id}}, socket) do
    running_apps =
      socket.assigns.running_apps
      |> Enum.map(fn {app_id, app} ->
        {app_id, %{app | selected: app_id == selected_app_id}}
      end)
      |> Map.new()

    {:noreply, socket |> assign(running_apps: running_apps)}
  end

  def handle_info({:apps, {:started, app_id, module}}, socket) do
    name = apply(module, :name, [])

    running_apps =
      socket.assigns.running_apps
      |> Map.put(app_id, %{
        module: module,
        name: name,
        selected: false
      })

    {:noreply, socket |> assign(running_apps: running_apps)}
  end

  def handle_info({:apps, {:stopped, app_id}}, socket) do
    running_apps = Map.delete(socket.assigns.running_apps, app_id)

    {:noreply, socket |> assign(running_apps: running_apps)}
  end

  def handle_info({:mixer, {:frame, frame}}, socket) do
    {:noreply, socket |> push_frame(frame)}
  end

  def handle_info({:mixer, {:config, config}}, socket) do
    {:noreply, socket |> push_config(config)}
  end

  defp assign_apps(socket) do
    available_apps =
      AppSupervisor.available_apps()
      |> Enum.map(&{to_string(&1), %{module: &1, name: apply(&1, :name, [])}})
      |> Map.new()

    selected_app = Mixer.selected_app()

    running_apps =
      AppSupervisor.running_apps()
      |> Enum.map(fn {module, app_id} ->
        {app_id,
         %{module: app_id, name: apply(module, :name, []), selected: app_id == selected_app}}
      end)
      |> Map.new()

    socket |> assign(available_apps: available_apps, running_apps: running_apps)
  end
end
