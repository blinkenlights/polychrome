defmodule OctopusWeb.SimulatorLive do
  use OctopusWeb, :live_view

  alias Octopus.Mixer
  alias Octopus.Protobuf.InputEvent
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
    <div
      class="flex w-full h-full justify-center bg-black"
      phx-window-keydown="keydown"
      phx-window-keyup="keyup"
    >
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

  @key_map %{
    "1" => :BUTTON_1,
    "2" => :BUTTON_2,
    "3" => :BUTTON_3,
    "4" => :BUTTON_4,
    "5" => :BUTTON_5,
    "6" => :BUTTON_6,
    "7" => :BUTTON_7,
    "8" => :BUTTON_8,
    "9" => :BUTTON_9,
    "0" => :BUTTON_10,
    "w" => :DIRECTION_1_UP,
    "a" => :DIRECTION_1_LEFT,
    "s" => :DIRECTION_1_DOWN,
    "d" => :DIRECTION_1_RIGHT,
    "q" => :BUTTON_A_1,
    "z" => :BUTTON_B_1,
    "y" => :BUTTON_B_1,
    "i" => :DIRECTION_2_UP,
    "j" => :DIRECTION_2_LEFT,
    "k" => :DIRECTION_2_DOWN,
    "l" => :DIRECTION_2_RIGHT,
    "u" => :BUTTON_A_2,
    "m" => :BUTTON_B_2
  }

  def handle_event("keydown", %{"key" => key}, socket) when is_map_key(@key_map, key) do
    button = @key_map[key]

    {button, value} =
      case button do
        :DIRECTION_1_LEFT -> {:AXIS_X_1, -1}
        :DIRECTION_1_RIGHT -> {:AXIS_X_1, 1}
        :DIRECTION_1_DOWN -> {:AXIS_Y_1, 1}
        :DIRECTION_1_UP -> {:AXIS_Y_1, -1}
        :DIRECTION_2_LEFT -> {:AXIS_X_2, -1}
        :DIRECTION_2_RIGHT -> {:AXIS_X_2, 1}
        :DIRECTION_2_DOWN -> {:AXIS_Y_2, 1}
        :DIRECTION_2_UP -> {:AXIS_Y_2, -1}
        _ -> {button, 1}
      end

    %InputEvent{type: button, value: value}
    |> Mixer.handle_input()

    {:noreply, socket}
  end

  def handle_event("keyup", %{"key" => key}, socket) when is_map_key(@key_map, key) do
    button = @key_map[key]

    {button, _} =
      case button do
        :DIRECTION_1_LEFT -> {:AXIS_X_1, 0}
        :DIRECTION_1_RIGHT -> {:AXIS_X_1, 0}
        :DIRECTION_1_UP -> {:AXIS_Y_1, 0}
        :DIRECTION_1_DOWN -> {:AXIS_Y_1, 0}
        :DIRECTION_2_LEFT -> {:AXIS_X_2, 0}
        :DIRECTION_2_RIGHT -> {:AXIS_X_2, 0}
        :DIRECTION_2_UP -> {:AXIS_Y_2, 0}
        :DIRECTION_2_DOWN -> {:AXIS_Y_2, 0}
        _ -> {button, 0}
      end

    %InputEvent{type: button, value: 0}
    |> Mixer.handle_input()

    {:noreply, socket}
  end

  def handle_event("keydown", _msg, socket) do
    {:noreply, socket}
  end

  def handle_event("keyup", _, socket) do
    {:noreply, socket}
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
