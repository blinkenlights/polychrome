defmodule OctopusWeb.ManagerLive do
  use OctopusWeb, :live_view

  alias Octopus.Canvas
  alias Octopus.Layout.Mildenberg
  alias Octopus.{Mixer, AppSupervisor}
  alias OctopusWeb.PixelsLive

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Mixer.subscribe()
      AppSupervisor.subscribe()
    end

    socket =
      socket
      |> assign(pixel_layout: Mildenberg.layout(), configure_app: nil)
      |> assign_apps()

    {:ok, socket, temporary_assigns: [pixel_layout: nil]}
  end

  def render(assigns) do
    ~H"""
    <div class="w-full" phx-window-keydown="keydown-event">
      <div class="flex w-full h-full justify-center bg-black">
        <%= live_render(@socket, PixelsLive, id: "main") %>
      </div>

      <div class="container mx-auto">
        <div class="border rounded m-2 p-0">
          <div class="flex flex-row">
            <div class="p-1 font-bold m-0 flex-grow">
              Running:
            </div>
            <div>
              <a href="/sim">
                <button
                  class="text-slate-800 background-transparent font-bold uppercase px-3 py-1 text-xs outline-none focus:outline-none mr-1 mb-1 ease-linear transition-all duration-150"
                  type="button"
                >
                  Open Sim
                </button>
              </a>
            </div>
          </div>
          <table class="w-full text-left m-0">
            <tbody>
              <tr :for={
                %{module: module, app_id: app_id, name: name, selected: selected} <- @running_apps
              }>
                <td class={"p-2 #{if selected, do: 'bg-slate-300 font-bold'}"}><%= name %></td>
                <td class={"p-2 #{if selected, do: 'bg-slate-300 font-bold'}"}><%= app_id %></td>
                <td class="flex flex-row gap-2 p-1 pl-3">
                  <button
                    class="border py-1 px-2 rounded  bg-slate-300"
                    phx-click="stop"
                    phx-value-module={module}
                    phx-value-app-id={app_id}
                  >
                    Stop
                  </button>

                  <.link navigate={~p"/app/#{app_id}"} class="border py-1 px-2 rounded bg-slate-300">
                    Configure
                  </.link>

                  <button
                    :if={!selected}
                    class="border py-1 px-2 rounded bg-slate-300"
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

        <div class="flex flex-col m-2">
          <div class="p-2 font-bold">
            Add App:
          </div>
          <div class="border p-2 flex flex-row flex-wrap">
            <div :for={%{module: module, name: name, icon: icon} <- @available_apps} class="m-0 p-1">
              <button
                class="border py-1 px-2 rounded bg-slate-500 text-white flex flex-row items-center gap-1"
                phx-click="start"
                phx-value-module={module}
              >
                <%= if icon do %>
                  <div class="w-5 h-5 inline-block rounded-sm overflow-hidden">
                    <%= raw(icon) %>
                  </div>
                <% end %>
                <%= name %>
              </button>
            </div>
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

  def handle_info({:mixer, {:frame, _frame}}, socket) do
    {:noreply, socket}
  end

  def handle_info({:mixer, {:config, _config}}, socket) do
    {:noreply, socket}
  end

  defp assign_apps(socket) do
    available_apps =
      for module <- AppSupervisor.available_apps() do
        name = apply(module, :name, [])

        icon =
          case apply(module, :icon, []) do
            nil -> nil
            canvas -> Canvas.to_svg(canvas, width: "100%", height: "100%")
          end

        %{module: module, name: name, icon: icon}
      end

    selected_app = Mixer.get_selected_app()

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
