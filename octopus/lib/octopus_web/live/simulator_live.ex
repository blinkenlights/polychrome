defmodule OctopusWeb.SimulatorLive do
  use OctopusWeb, :live_view

  alias Octopus.Layout.{Mildenberg, MildenbergZoom1, MildenbergZoom2}
  alias OctopusWeb.PixelsComponent

  import PixelsComponent, only: [pixels: 1]

  @views %{
    "default" => Mildenberg.layout(),
    "zoom1" => MildenbergZoom1.layout(),
    "zoom2" => MildenbergZoom2.layout()
  }

  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(
        pixel_layout: @views["default"],
        window: 1,
        view: "default",
        view_options: Enum.map(@views, fn {k, v} -> [key: v.name, value: k] end)
      )
      |> PixelsComponent.setup()

    {:ok, assign(socket, window: 0, view: "default")}
  end

  def handle_params(params, _uri, socket) do
    view = if Map.has_key?(@views, params["view"]), do: params["view"], else: "default"
    pixel_layout = Map.get(@views, view)

    {window, pixel_offset} =
      case view do
        "default" ->
          {1, 0}

        _ ->
          {window, _} = Map.get(params, "window", "1") |> Integer.parse()
          window = max(1, min(10, window))
          {window, (window - 1) * 64}
      end

    socket =
      socket
      |> assign(
        pixel_layout: pixel_layout,
        window: window,
        view: view
      )
      |> PixelsComponent.push_layout(pixel_layout)
      |> PixelsComponent.push_pixel_offset(pixel_offset)

    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="flex w-full h-full justify-center bg-black">
      <div class="fixed top-4 flex flex-col gap-2 z-10">
        <form id="view-form" phx-change="view-changed">
          <.input type="select" name="view" options={@view_options} value={@view} />
        </form>
        <div :if={@view != "default"}>
          <.link
            :for={window <- 1..10}
            patch={~p"/sim?#{%{view: @view, window: window}}"}
            class="bg-neutral-900/20 text-neutral-100 rounded inline-block mx-1 w-6 border border-neutral-500 shadow text-center"
          >
            <%= window %>
          </.link>
        </div>
      </div>
      <.pixels id="pixels" pixel_layout={@pixel_layout} />
    </div>
    """
  end

  def handle_event("view-changed", %{"view" => view}, socket) do
    {:noreply, socket |> push_patch(to: ~p"/sim?#{%{view: view, window: socket.assigns.window}}")}
  end

  def handle_info({:mixer, {:frame, frame}}, socket) do
    {:noreply, socket |> PixelsComponent.push_frame(frame)}
  end

  def handle_info({:mixer, {:config, config}}, socket) do
    {:noreply, socket |> PixelsComponent.push_config(config)}
  end

  # Ignore other mixer events. We are only interested in the mixer output.
  def handle_info({:mixer, _}, socket) do
    {:noreply, socket}
  end
end
