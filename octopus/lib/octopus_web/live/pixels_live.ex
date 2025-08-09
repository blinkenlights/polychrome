defmodule OctopusWeb.PixelsLive do
  use OctopusWeb, :live_view

  import Phoenix.LiveView, only: [push_event: 3, connected?: 1]

  alias Octopus.{Events, Mixer}
  alias Octopus.Protobuf.{FirmwareConfig, RGBFrame}
  alias Octopus.Events.Event.Input, as: InputEvent
  alias Octopus.Installation

  @default_config %FirmwareConfig{
    easing_mode: :LINEAR,
    show_test_frame: false
  }

  @id_prefix "pixels"

  defp get_views() do
    layouts = Installation.simulator_layouts()

    # Create a map with indexed layout keys to ensure uniqueness
    layouts
    |> Enum.with_index()
    |> Enum.into(%{}, fn {layout, index} ->
      # Use the layout name, but sanitize it for use as a map key
      key = layout.name |> String.downcase() |> String.replace(~r/[^a-z0-9]/, "_")
      # Always append index to ensure uniqueness
      unique_key = "#{key}_#{index}"
      {unique_key, layout}
    end)
  end

  # Will be set to the first layout key dynamically

  defp get_key_map() do
    num_buttons = Installation.num_buttons()

    # Base button mappings for number keys and function keys
    button_mappings =
      for i <- 1..min(num_buttons, 10)//1 do
        key = if i == 10, do: "0", else: to_string(i)
        {key, i}
      end ++
        for i <- 1..min(num_buttons, 12)//1 do
          key = "F#{i}"
          {key, i}
        end

    # Joystick mappings
    joystick_mappings = [
      # Joystick 1 directions: A,S,D,F = left,down,up,right
      {"a", :JOYSTICK_1_LEFT},
      {"s", :JOYSTICK_1_DOWN},
      {"d", :JOYSTICK_1_UP},
      {"f", :JOYSTICK_1_RIGHT},

      # Joystick 1 buttons: X,C = a,b
      {"x", :JOYSTICK_1_A},
      {"c", :JOYSTICK_1_B},

      # Joystick 2 directions: H,J,K,L = left,down,up,right
      {"h", :JOYSTICK_2_LEFT},
      {"j", :JOYSTICK_2_DOWN},
      {"k", :JOYSTICK_2_UP},
      {"l", :JOYSTICK_2_RIGHT},

      # Joystick 2 buttons: N,M = a,b
      {"n", :JOYSTICK_2_A},
      {"m", :JOYSTICK_2_B}
    ]

    (button_mappings ++ joystick_mappings) |> Enum.into(%{})
  end

  def mount(_params, _session, socket) do
    views = get_views()
    default_view = views |> Map.keys() |> List.first()
    pixel_layout = views[default_view]

    socket =
      if connected?(socket) do
        Mixer.subscribe()

        frame = %RGBFrame{
          data:
            [0, 0, 0]
            |> List.duplicate(pixel_layout.width * pixel_layout.height)
            |> IO.iodata_to_binary()
        }

        socket
        |> push_layout(views[default_view])
        |> push_config(@default_config)
        |> push_frame(frame)
        |> push_pixel_offset(0)
      else
        socket
      end

    view_options = Enum.map(views, fn {k, v} -> [key: v.name, value: k] end)
    max_windows = Installation.num_panels()
    num_buttons = Installation.num_buttons()

    {:ok,
     socket
     |> assign(
       id: socket.id,
       id_prefix: @id_prefix,
       pixel_layout: views[default_view],
       view: default_view,
       default_view: default_view,
       view_options: view_options,
       views: views,
       max_windows: max_windows,
       window: 1,
       num_buttons: num_buttons,
       key_map: get_key_map(),
       pressed_buttons: MapSet.new()
     )}
  end

  def render(assigns) do
    ~H"""
    <div
      class="flex w-full h-full justify-center bg-black"
      phx-window-keydown="keydown"
      phx-window-keyup="keyup"
    >
      <div class="absolute top-4 flex flex-col gap-3 z-10">
        <!-- Playlist Information -->
        <form id="view-form" phx-change="view-changed">
          <.input type="select" name="view" options={@view_options} value={@view} />
        </form>
        <div :if={@view != @default_view} class="flex gap-1">
          <button
            :for={window <- 1..@max_windows}
            phx-click="window-changed"
            phx-value-window={window}
            class={[
              "btn btn-sm btn-square",
              if(@window == window, do: "btn-primary", else: "btn-outline btn-primary")
            ]}
          >
            {window}
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

    <!-- Button UI Panel - Bottom -->
        <div class="absolute bottom-4 left-1/2 transform -translate-x-1/2 z-10">
          <div class="flex gap-2 justify-center">
            <button
              :for={i <- 1..@num_buttons//1}
              phx-click="button-click"
              phx-value-button={i}
              class={[
                "btn btn-sm font-mono min-w-[2.5rem]",
                if MapSet.member?(@pressed_buttons, i) do
                  "btn-success"
                else
                  "btn-neutral"
                end
              ]}
              type="button"
            >
              {i}
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def handle_event("view-changed", %{"view" => view}, socket) do
    views = socket.assigns.views
    default_view = views |> Map.keys() |> List.first()
    view = if Map.has_key?(views, view), do: view, else: default_view
    pixel_layout = Map.get(views, view)

    socket =
      socket
      |> push_layout(pixel_layout)
      |> push_pixel_offset(0)
      |> assign(view: view, pixel_layout: pixel_layout)

    {:noreply, socket}
  end

  def handle_event("window-changed", %{"window" => window_string}, socket) do
    views = socket.assigns.views
    default_view = views |> Map.keys() |> List.first()

    {window, pixel_offset} =
      case socket.assigns.view do
        ^default_view ->
          {1, 0}

        _ ->
          {window, _} = Integer.parse(window_string)
          max_windows = socket.assigns.max_windows
          window = max(1, min(max_windows, window))
          {window, (window - 1) * 64}
      end

    socket =
      socket
      |> push_pixel_offset(pixel_offset)
      |> assign(window: window)

    {:noreply, socket}
  end

  def handle_event("keydown", %{"key" => key}, socket) do
    key_map = socket.assigns.key_map

    if Map.has_key?(key_map, key) do
      key_value = key_map[key]

      case key_value do
        # Screen buttons (numbered based on installation)
        button_num when is_integer(button_num) ->
          socket =
            socket
            |> assign(pressed_buttons: MapSet.put(socket.assigns.pressed_buttons, button_num))

          %InputEvent{type: :button, button: button_num, action: :press}
          |> Events.handle_event()

          {:noreply, socket}

        :JOYSTICK_1_LEFT ->
          %InputEvent{type: :joystick, joystick: 1, direction: :left}
          |> Events.handle_event()

          {:noreply, socket}

        :JOYSTICK_1_DOWN ->
          %InputEvent{type: :joystick, joystick: 1, direction: :down}
          |> Events.handle_event()

          {:noreply, socket}

        :JOYSTICK_1_UP ->
          %InputEvent{type: :joystick, joystick: 1, direction: :up}
          |> Events.handle_event()

          {:noreply, socket}

        :JOYSTICK_1_RIGHT ->
          %InputEvent{type: :joystick, joystick: 1, direction: :right}
          |> Events.handle_event()

          {:noreply, socket}

        :JOYSTICK_1_A ->
          %InputEvent{type: :joystick, joystick: 1, joy_button: :a, action: :press}
          |> Events.handle_event()

          {:noreply, socket}

        :JOYSTICK_1_B ->
          %InputEvent{type: :joystick, joystick: 1, joy_button: :b, action: :press}
          |> Events.handle_event()

          {:noreply, socket}

        :JOYSTICK_2_LEFT ->
          %InputEvent{type: :joystick, joystick: 2, direction: :left}
          |> Events.handle_event()

          {:noreply, socket}

        :JOYSTICK_2_DOWN ->
          %InputEvent{type: :joystick, joystick: 2, direction: :down}
          |> Events.handle_event()

          {:noreply, socket}

        :JOYSTICK_2_UP ->
          %InputEvent{type: :joystick, joystick: 2, direction: :up}
          |> Events.handle_event()

          {:noreply, socket}

        :JOYSTICK_2_RIGHT ->
          %InputEvent{type: :joystick, joystick: 2, direction: :right}
          |> Events.handle_event()

          {:noreply, socket}

        :JOYSTICK_2_A ->
          %InputEvent{type: :joystick, joystick: 2, joy_button: :a, action: :press}
          |> Events.handle_event()

          {:noreply, socket}

        :JOYSTICK_2_B ->
          %InputEvent{type: :joystick, joystick: 2, joy_button: :b, action: :press}
          |> Events.handle_event()

          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("keyup", %{"key" => key}, socket) do
    key_map = socket.assigns.key_map

    if Map.has_key?(key_map, key) do
      key_value = key_map[key]

      case key_value do
        # Screen buttons (numbered based on installation)
        button_num when is_integer(button_num) ->
          socket =
            socket
            |> assign(pressed_buttons: MapSet.delete(socket.assigns.pressed_buttons, button_num))

          %InputEvent{type: :button, button: button_num, action: :release}
          |> Events.handle_event()

          {:noreply, socket}

        # Joystick directions - return to center on keyup
        joystick_direction
        when joystick_direction in [
               :JOYSTICK_1_LEFT,
               :JOYSTICK_1_DOWN,
               :JOYSTICK_1_UP,
               :JOYSTICK_1_RIGHT
             ] ->
          %InputEvent{type: :joystick, joystick: 1, direction: :center}
          |> Events.handle_event()

          {:noreply, socket}

        joystick_direction
        when joystick_direction in [
               :JOYSTICK_2_LEFT,
               :JOYSTICK_2_DOWN,
               :JOYSTICK_2_UP,
               :JOYSTICK_2_RIGHT
             ] ->
          %InputEvent{type: :joystick, joystick: 2, direction: :center}
          |> Events.handle_event()

          {:noreply, socket}

        :JOYSTICK_1_A ->
          %InputEvent{type: :joystick, joystick: 1, joy_button: :a, action: :release}
          |> Events.handle_event()

          {:noreply, socket}

        :JOYSTICK_1_B ->
          %InputEvent{type: :joystick, joystick: 1, joy_button: :b, action: :release}
          |> Events.handle_event()

          {:noreply, socket}

        :JOYSTICK_2_A ->
          %InputEvent{type: :joystick, joystick: 2, joy_button: :a, action: :release}
          |> Events.handle_event()

          {:noreply, socket}

        :JOYSTICK_2_B ->
          %InputEvent{type: :joystick, joystick: 2, joy_button: :b, action: :release}
          |> Events.handle_event()

          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("button-click", %{"button" => button_string}, socket) do
    {button_num, _} = Integer.parse(button_string)

    socket =
      socket
      |> assign(pressed_buttons: MapSet.put(socket.assigns.pressed_buttons, button_num))

    %InputEvent{type: :button, button: button_num, action: :press}
    |> Events.handle_event()

    # Simulate button press with automatic release after delay
    Process.send_after(self(), {:button_release, button_num}, 100)

    {:noreply, socket}
  end

  def handle_info({:button_release, button_num}, socket) do
    socket =
      socket
      |> assign(pressed_buttons: MapSet.delete(socket.assigns.pressed_buttons, button_num))

    %InputEvent{type: :button, button: button_num, action: :release}
    |> Events.handle_event()

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
