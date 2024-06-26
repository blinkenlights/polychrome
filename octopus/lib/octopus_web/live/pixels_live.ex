defmodule OctopusWeb.PixelsLive do
  alias Octopus.Layout.Nation
  use OctopusWeb, :live_view

  import Phoenix.LiveView, only: [push_event: 3, connected?: 1]

  alias Octopus.ColorPalette
  alias Octopus.Mixer
  alias Octopus.Protobuf.{FirmwareConfig, Frame, InputEvent}

  @default_config %FirmwareConfig{
    easing_mode: :LINEAR,
    show_test_frame: false
  }

  @id_prefix "pixels"

  @views %{
    "default" => Nation.layout()
  }

  @default_view "default"

  def mount(_params, _session, socket) do
    pixel_layout = Nation.layout()

    socket =
      if connected?(socket) do
        Mixer.subscribe()

        frame = %Frame{
          data: List.duplicate(0, pixel_layout.width * pixel_layout.height),
          palette: ColorPalette.load("pico-8")
        }

        socket
        |> push_layout(@views[@default_view])
        |> push_config(@default_config)
        |> push_frame(frame)
        |> push_pixel_offset(0)
      else
        socket
      end

    view_options = Enum.map(@views, fn {k, v} -> [key: v.name, value: k] end)

    {:ok,
     socket
     |> assign(
       id: socket.id,
       id_prefix: @id_prefix,
       pixel_layout: @views[@default_view],
       view: @default_view,
       view_options: view_options,
       window: 1
     )}
  end

  def render(assigns) do
    ~H"""
    <div
      class="flex w-full h-full justify-center bg-black"
      phx-window-keydown="keydown"
      phx-window-keyup="keyup"
    >
      <div class="absolute top-4 flex flex-col gap-2 z-10">
        <form id="view-form" phx-change="view-changed">
          <.input type="select" name="view" options={@view_options} value={@view} />
        </form>
        <div :if={@view != "default"}>
          <button
            :for={window <- 1..10}
            phx-click="window-changed"
            phx-value-window={window}
            class={[
              if(@window == window, do: "bg-neutral-100/20", else: "bg-neutral-900/20"),
              "text-neutral-100 rounded inline-block mx-1 w-6 border border-neutral-500 shadow text-center"
            ]}
          >
            <%= window %>
          </button>
        </div>
      </div>
      <div class="w-full h-full float-left relative">
        <canvas
          id={"#{@id_prefix}-#{@id}"}
          phx-hook="Pixels"
          class="w-full h-full bg-contain bg-no-repeat bg-center"
          style={"background-image: url(#{@pixel_layout.background_image});"}
        />
        <%!-- <img
          src={@pixel_layout.pixel_image}
          class="absolute left-0 top-0 w-full h-full object-contain mix-blend-multiply pointer-events-none"
        /> --%>
      </div>
    </div>
    """
  end

  def handle_event("view-changed", %{"view" => view}, socket) do
    view = if Map.has_key?(@views, view), do: view, else: @default_view
    pixel_layout = Map.get(@views, view)

    socket =
      socket
      |> push_layout(pixel_layout)
      |> push_pixel_offset(0)
      |> assign(view: view, pixel_layout: pixel_layout)

    {:noreply, socket}
  end

  def handle_event("window-changed", %{"window" => window_string}, socket) do
    {window, pixel_offset} =
      case socket.assigns.view do
        "default" ->
          {1, 0}

        _ ->
          {window, _} = Integer.parse(window_string)
          window = max(1, min(10, window))
          {window, (window - 1) * 64}
      end

    socket =
      socket
      |> push_pixel_offset(pixel_offset)
      |> assign(window: window)

    {:noreply, socket}
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
    "i" => :DIRECTION_2_UP,
    "j" => :DIRECTION_2_LEFT,
    "k" => :DIRECTION_2_DOWN,
    "l" => :DIRECTION_2_RIGHT,
    "u" => :BUTTON_A_2,
    "m" => :BUTTON_MENU
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
    {:noreply, socket |> push_frame(frame)}
  end

  def handle_info({:mixer, {:config, config}}, socket) do
    {:noreply, socket |> push_config(config)}
  end

  def handle_info({:mixer, _msg}, socket) do
    {:noreply, socket}
  end

  defp push_layout(socket, layout) do
    push_event(socket, "layout:#{@id_prefix}-#{socket.id}", %{layout: layout})
  end

  defp push_frame(socket, frame) do
    push_event(socket, "frame:#{@id_prefix}-#{socket.id}", %{frame: frame})
  end

  defp push_config(socket, config) do
    push_event(socket, "config:#{@id_prefix}-#{socket.id}", %{config: config})
  end

  defp push_pixel_offset(socket, offset) do
    push_event(socket, "pixel_offset:#{@id_prefix}-#{socket.id}", %{offset: offset})
  end
end
