defmodule OctopusWeb.PixelsLive do
  use OctopusWeb, :live_view

  import Phoenix.LiveView, only: [push_event: 3, connected?: 1]
  import OctopusWeb.PanelStatusComponent

  alias Octopus.{Broadcaster, Events, Mixer}
  alias Octopus.Hardware.PanelStatus
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

  def mount(_params, session, socket) do
    embedded = session["embedded"] in [true, "true"]
    views = get_views()
    default_view = views |> Map.keys() |> List.first()
    pixel_layout = views[default_view]
    panel_status_visible = Installation.num_panels() > 0
    sending_to_panels = Broadcaster.sending_enabled?()

    socket =
      if connected?(socket) do
        Mixer.subscribe()

        frame = %RGBFrame{
          data:
            [0, 0, 0]
            |> List.duplicate(pixel_layout.width * pixel_layout.height)
            |> IO.iodata_to_binary()
        }

        socket =
          socket
          |> push_layout(views[default_view])
          |> push_config(@default_config)
          |> push_frame(frame)
          |> push_pixel_offset(0)

        socket =
          if panel_status_visible do
            Broadcaster.subscribe_sending_changes()
            subscribe_panel_status(socket)
          else
            socket
          end

        if panel_status_visible do
          :timer.send_interval(1_000, :refresh_panel_status)
          send(self(), :refresh_panel_status)
        end

        socket
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
       embedded: embedded,
       pixel_layout: views[default_view],
       view: default_view,
       default_view: default_view,
       view_options: view_options,
       views: views,
       max_windows: max_windows,
       window: 1,
       num_buttons: num_buttons,
       key_map: get_key_map(),
       pressed_buttons: MapSet.new(),
       panel_status_visible: panel_status_visible,
       sending_to_panels: sending_to_panels,
       panel_statuses: initial_panel_statuses(panel_status_visible),
       current_time: System.os_time(:second),
       channel_mode: :mix,
       has_mask: false
     )}
  end

  def render(assigns) do
    ~H"""
    <div
      class={[
        "flex w-full justify-center bg-black",
        @embedded && "sim-embedded-root relative h-full flex-col items-stretch min-h-0",
        !@embedded && "h-full min-h-screen"
      ]}
      phx-window-keydown="keydown"
      phx-window-keyup="keyup"
    >
      <div class="absolute top-2 left-2 z-10">
        <.panel_status_boxes
          visible={@panel_status_visible}
          sending_enabled={@sending_to_panels}
          panel_statuses={@panel_statuses}
          current_time={@current_time}
        />
      </div>

      <div class="absolute top-2 left-1/2 -translate-x-1/2 z-10">
        <div class="join">
          <button
            phx-click="channel-mode"
            phx-value-mode="mix"
            class={[
              "join-item btn btn-xs",
              if(@channel_mode == :mix, do: "btn-primary", else: "btn-outline btn-primary")
            ]}
          >
            Mix
          </button>
          <button
            phx-click="channel-mode"
            phx-value-mode="front"
            class={[
              "join-item btn btn-xs",
              if(@channel_mode == :front, do: "btn-primary", else: "btn-outline btn-primary")
            ]}
          >
            Front
          </button>
          <button
            phx-click="channel-mode"
            phx-value-mode="mask"
            disabled={not @has_mask}
            class={[
              "join-item btn btn-xs",
              if(@channel_mode == :mask, do: "btn-secondary", else: "btn-outline btn-secondary"),
              not @has_mask && "opacity-40"
            ]}
          >
            Mask
          </button>
        </div>
      </div>

      <div class="absolute top-2 right-2 flex flex-col items-end gap-1.5 z-10">
        <form id="view-form" phx-change="view-changed">
          <select
            id="view-select"
            name="view"
            class="select select-bordered select-xs w-40 text-xs"
          >
            {Phoenix.HTML.Form.options_for_select(@view_options, @view)}
          </select>
        </form>
        <div :if={@view != @default_view} class="flex gap-1 justify-end">
          <button
            :for={window <- 1..@max_windows}
            phx-click="window-changed"
            phx-value-window={window}
            class={[
              "btn btn-xs btn-square",
              if(@window == window, do: "btn-primary", else: "btn-outline btn-primary")
            ]}
          >
            {window}
          </button>
        </div>
      </div>

      <%= if @embedded do %>
        <div class="sim-embedded-canvas flex-1 min-h-0 w-full flex items-center justify-center px-4 pt-14">
          <canvas
            id={"#{@id_prefix}-#{@id}"}
            phx-hook="Pixels"
            phx-update="ignore"
            class="max-h-full max-w-full w-full h-full bg-contain bg-no-repeat bg-center"
            style={"background-image: url(#{@pixel_layout.background_image});"}
          />
        </div>
        <.button_panel num_buttons={@num_buttons} pressed_buttons={@pressed_buttons} class="shrink-0 pb-3 pt-1" />
      <% else %>
        <div class="w-full h-full float-left relative">
          <canvas
            id={"#{@id_prefix}-#{@id}"}
            phx-hook="Pixels"
            phx-update="ignore"
            class="w-full h-full bg-contain bg-no-repeat bg-center"
            style={"background-image: url(#{@pixel_layout.background_image});"}
          />
          <.button_panel
            num_buttons={@num_buttons}
            pressed_buttons={@pressed_buttons}
            class="absolute bottom-4 left-1/2 -translate-x-1/2 z-10"
          />
        </div>
      <% end %>
    </div>
    """
  end

  attr :num_buttons, :integer, required: true
  attr :pressed_buttons, :any, required: true
  attr :class, :string, default: nil

  defp button_panel(assigns) do
    ~H"""
    <div class={["flex justify-center", @class]}>
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
    """
  end

  def handle_event("channel-mode", %{"mode" => mode_string}, socket) do
    channel_mode =
      case mode_string do
        "front" -> :front
        "mask" -> :mask
        _ -> :mix
      end

    {:noreply, assign(socket, channel_mode: channel_mode)}
  end

  def handle_event("toggle-panel-sending", _params, socket) do
    Broadcaster.set_sending_enabled(!socket.assigns.sending_to_panels)
    {:noreply, socket}
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

  def handle_info({:panel_status, panel, status}, %{assigns: %{panel_status_visible: true}} = socket) do
    panel_statuses =
      Enum.map(socket.assigns.panel_statuses, fn entry ->
        if entry.panel == panel, do: %{entry | status: status}, else: entry
      end)

    {:noreply, assign(socket, panel_statuses: panel_statuses)}
  end

  def handle_info(:refresh_panel_status, %{assigns: %{panel_status_visible: true}} = socket) do
    {:noreply,
     assign(socket,
       panel_statuses: PanelStatus.all(),
       current_time: System.os_time(:second)
     )}
  end

  def handle_info({:sending_changed, enabled}, socket) do
    socket =
      socket
      |> assign(sending_to_panels: enabled)
      |> then(fn socket ->
        if enabled do
          assign(socket,
            panel_statuses: PanelStatus.all(),
            current_time: System.os_time(:second)
          )
        else
          socket
        end
      end)

    {:noreply, socket}
  end

  def handle_info(:refresh_panel_status, socket) do
    {:noreply, socket}
  end

  def handle_info({:panel_status, _panel, _status}, socket) do
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
    case socket.assigns.channel_mode do
      :mix -> {:noreply, push_frame(socket, frame)}
      :front when not socket.assigns.has_mask -> {:noreply, push_frame(socket, frame)}
      _ -> {:noreply, socket}
    end
  end

  def handle_info({:mixer, {:front_frame, frame}}, socket) do
    if socket.assigns.channel_mode == :front do
      {:noreply, push_frame(socket, frame)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:mixer, {:mask_frame, frame}}, socket) do
    socket = if not socket.assigns.has_mask, do: assign(socket, has_mask: true), else: socket

    if socket.assigns.channel_mode == :mask do
      {:noreply, push_frame(socket, frame)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:mixer, {:output_mode, output_mode}}, socket) do
    has_mask = output_mode == :masked

    channel_mode =
      if not has_mask and socket.assigns.channel_mode == :mask do
        :mix
      else
        socket.assigns.channel_mode
      end

    {:noreply, assign(socket, has_mask: has_mask, channel_mode: channel_mode)}
  end

  def handle_info({:mixer, {:config, config}}, socket) do
    {:noreply, push_config(socket, config)}
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

  defp subscribe_panel_status(socket) do
    PanelStatus.subscribe()
    socket
  end

  defp initial_panel_statuses(true), do: PanelStatus.all()
  defp initial_panel_statuses(false), do: []
end
