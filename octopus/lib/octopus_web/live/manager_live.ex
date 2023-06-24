defmodule OctopusWeb.ManagerLive do
  use OctopusWeb, :live_view

  alias Octopus.Layout.Mildenberg
  alias Octopus.Protobuf.InputEvent
  alias Octopus.{Mixer, AppSupervisor}
  alias OctopusWeb.PixelsComponent

  import PixelsComponent, only: [pixels: 1]

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Mixer.subscribe()
      AppSupervisor.subscribe()
    end

    socket =
      socket
      |> assign(pixel_layout: Mildenberg.layout(), configure_app: nil)
      |> assign_apps()
      |> PixelsComponent.setup()

    {:ok, socket, temporary_assigns: [pixel_layout: nil]}
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
                <tr :for={%{module: module, name: name} <- @available_apps}>
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
                  %{module: module, app_id: app_id, name: name, selected: selected} <- @running_apps
                }>
                  <td><%= name %></td>
                  <td><%= app_id %></td>
                  <td class="flex flex-row gap-2">
                    <button
                      class="border py-1 px-2 rounded"
                      phx-click="stop"
                      phx-value-module={module}
                      phx-value-app-id={app_id}
                    >
                      Stop
                    </button>

                    <.link navigate={~p"/app/#{app_id}"} class="border py-1 px-2 rounded">
                      Configure
                    </.link>

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
    module = String.to_existing_atom(module_string)
    {:ok, _} = AppSupervisor.start_app(module)
    {:noreply, socket}
  end

  def handle_event("stop", %{"app-id" => app_id}, socket) do
    AppSupervisor.stop_app(app_id)

    {:noreply, socket}
  end

  def handle_event("select", %{"app-id" => app_id}, socket) do
    Mixer.select_app(app_id)

    {:noreply, socket}
  end

  # todo: handle keyup event
  def handle_event("keydown-event", %{"key" => key}, socket)
      when key in ~w(0 1 2 3 4 5 6 7 8 9) do
    button =
      case key do
        "0" -> :BUTTON_10
        int -> String.to_existing_atom("BUTTON_#{int}")
      end

    %InputEvent{type: button, value: 1}
    |> Mixer.handle_input()

    {:noreply, socket}
  end

  def handle_event("keydown-event", %{"key" => _other_key}, socket) do
    {:noreply, socket}
  end

  def handle_event("configure", %{"app-id" => app_id}, socket) do
    {:noreply, socket |> assign(configure_app: app_id)}
  end

  def handle_info({:apps, _}, socket) do
    {:noreply, socket |> assign_apps()}
  end

  def handle_info({:mixer, {:selected_app, _selected_app_id}}, socket) do
    {:noreply, socket |> assign_apps()}
  end

  def handle_info({:mixer, {:frame, frame}}, socket) do
    {:noreply, socket |> PixelsComponent.push_frame(frame)}
  end

  def handle_info({:mixer, {:config, config}}, socket) do
    {:noreply, socket |> PixelsComponent.push_config(config)}
  end

  defp assign_apps(socket) do
    available_apps =
      for module <- AppSupervisor.available_apps() do
        %{module: module, name: apply(module, :name, [])}
      end

    selected_app = Mixer.selected_app()

    running_apps =
      for {module, app_id} <- AppSupervisor.running_apps() do
        %{
          module: module,
          app_id: app_id,
          name: apply(module, :name, []),
          selected: app_id == selected_app
        }
      end

    socket |> assign(available_apps: available_apps, running_apps: running_apps)
  end
end
