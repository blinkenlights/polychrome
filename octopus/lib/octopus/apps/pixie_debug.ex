defmodule Octopus.Apps.PixieDebug do
  use Octopus.App, category: :test

  require Logger

  alias Octopus.AppSupervisor
  alias Octopus.Canvas
  alias Octopus.Events.Event.Input, as: InputEvent
  alias Octopus.Hardware
  alias Octopus.Hardware.WireMap
  alias Octopus.Installation

  @pixel_walk_mode "pixel_walk"
  @full_panel_mode "full_panel"
  @max_index 63

  defmodule State do
    defstruct [
      :mode_id,
      :layout_index,
      :color_channel,
      :color,
      :display_info
    ]
  end

  def name(), do: "Pixie Debug"

  def rotation_eligible?(), do: false

  def compatible?() do
    installation = Octopus.App.get_installation_info()

    installation.panel_count == 1 and installation.panel_width == 8 and
      installation.panel_height == 8
  end

  def list_modes do
    [
      %{
        id: @pixel_walk_mode,
        name: "Pixel walk",
        accent_color: "#888888",
        summary: "Walk a single white pixel across the panel for wiring debug",
        builtin: true
      },
      %{
        id: @full_panel_mode,
        name: "Full panel",
        accent_color: "#6d7cff",
        summary: "Fill the entire 8×8 panel with white or RGB color",
        builtin: true
      }
    ]
  end

  def mode_config(mode_id), do: mode_config_for(mode_id)

  def mode_tweakables(mode_id), do: mode_tweakables_for(mode_id)

  def apply_mode(app_id, mode_id) do
    AppSupervisor.update_config(app_id, mode_config(to_string(mode_id)))
  end

  def config_schema do
    %{
      mode_id: {"Mode", :internal, %{default: @pixel_walk_mode}},
      layout_index:
        {"Layout index", :int,
         %{
           min: 0,
           max: @max_index,
           default: 0,
           visible_when: {:mode_id, [@pixel_walk_mode]}
         }},
      color_channel:
        {"Color channel", :select,
         %{
           default: 0,
           options: [{"White", :white}, {"RGB", :rgb}],
           visible_when: {:mode_id, [@full_panel_mode]}
         }},
      color:
        {"Color", :color,
         %{
           default: "#ffffff",
           visible_when: {:color_channel, [:rgb]}
         }}
    }
  end

  def get_config(%State{} = state) do
    %{
      mode_id: state.mode_id,
      layout_index: state.layout_index,
      color_channel: state.color_channel,
      color: state.color
    }
  end

  def handle_config(config, %State{} = state) do
    state = apply_config(state, config)
    {:noreply, render_state(state)}
  end

  def config_info(%{mode_id: @full_panel_mode} = config) do
    case Map.get(config, :color_channel, :white) do
      :rgb -> "Panel fill · #{Map.get(config, :color, "#ffffff")} (RGB)"
      _ -> "Panel fill · white"
    end
  end

  def config_info(%{layout_index: layout_index}) do
    info = debug_info(layout_index)

    """
    Layout (#{info.x}, #{info.y})
    Strip position: #{info.strip}
    Firmware buffer index: #{info.firmware_index}
    """
  end

  def config_info(_config), do: nil

  def now_playing_meta(%{mode_id: @full_panel_mode} = config) do
    case Map.get(config, :color_channel, :white) do
      :rgb -> ["Panel fill · #{Map.get(config, :color, "#ffffff")} (RGB)"]
      _ -> ["Panel fill · white"]
    end
  end

  def now_playing_meta(%{mode_id: @pixel_walk_mode, layout_index: layout_index}) do
    info = debug_info(layout_index)

    [
      "Layout (#{info.x}, #{info.y})",
      "Strip position: #{info.strip}",
      "Firmware buffer index: #{info.firmware_index}"
    ]
  end

  def now_playing_meta(%{layout_index: layout_index}) do
    info = debug_info(layout_index)

    [
      "Layout (#{info.x}, #{info.y})",
      "Strip position: #{info.strip}",
      "Firmware buffer index: #{info.firmware_index}"
    ]
  end

  def now_playing_meta(_config), do: []

  def debug_info(layout_index) when is_integer(layout_index) do
    slot = hd(Installation.panel_slots())
    controller = Hardware.fetch!(slot.controller_id)
    wiring = Hardware.fetch_wiring!(slot.wiring_id)
    layout = Installation.panel_layout()
    panel_width = elem(layout, 0)
    {x, y} = layout_coords(layout_index, panel_width)

    strip = WireMap.layout_to_strip(layout_index, wiring, elem(layout, 0), elem(layout, 1))

    firmware_index =
      WireMap.firmware_index_for_layout(x, y, layout, wiring, controller)

    %{x: x, y: y, strip: strip, firmware_index: firmware_index}
  end

  def app_init(config) do
    Octopus.App.configure_display(
      layout: :gapped_panels,
      supports_rgb: true,
      supports_grayscale: true
    )

    Octopus.App.subscribe_to_button_events()

    display_info = Octopus.App.get_display_info()

    state =
      %State{display_info: display_info}
      |> apply_config(config)

    render_state(state)

    {:ok, state}
  end

  def handle_event(
        %InputEvent{type: :button, action: :press, button: 1},
        %State{mode_id: @pixel_walk_mode} = state
      ) do
    last = max_index(state)
    next_index = if state.layout_index >= last, do: 0, else: state.layout_index + 1
    {:noreply, apply_layout_index(state, next_index)}
  end

  def handle_event(_event, state), do: {:noreply, state}

  @doc false
  def build_canvas(%State{mode_id: @full_panel_mode} = state) do
    case state.color_channel do
      :rgb ->
        {r, g, b} = parse_hex_color(state.color)
        Canvas.new(state.display_info.width, state.display_info.height, :rgb)
        |> Canvas.fill({r, g, b})

      _ ->
        Canvas.new(state.display_info.width, state.display_info.height, :grayscale)
        |> Canvas.fill(255)
    end
  end

  def build_canvas(%State{} = state) do
    canvas = Canvas.new(state.display_info.width, state.display_info.height)
    {x, y} = layout_coords(state.layout_index, state.display_info.panel_width)

    case state.display_info.panel_to_global_coords.(0, x, y) do
      :invalid_panel ->
        canvas

      {gx, gy} ->
        Canvas.put_pixel(canvas, {gx, gy}, {255, 255, 255})
    end
  end

  defp mode_config_for(@pixel_walk_mode),
    do: %{mode_id: @pixel_walk_mode, layout_index: 0}

  defp mode_config_for(@full_panel_mode),
    do: %{mode_id: @full_panel_mode, color_channel: :white, color: "#ffffff"}

  defp mode_config_for(_), do: %{}

  defp mode_tweakables_for(@pixel_walk_mode) do
    [
      %{
        key: :layout_index,
        label: "Layout index",
        type: :slider,
        min: 0,
        max: @max_index,
        step: 1,
        default: 0
      }
    ]
  end

  defp mode_tweakables_for(@full_panel_mode) do
    [
      %{
        key: :color_channel,
        label: "Color channel",
        type: :choice,
        default: :white,
        options: [{:white, "White"}, {:rgb, "RGB"}]
      },
      %{
        key: :color,
        label: "Color",
        type: :color,
        default: "#ffffff",
        visible_when: {:color_channel, [:rgb]}
      }
    ]
  end

  defp mode_tweakables_for(_), do: []

  defp apply_config(%State{} = state, config) do
    display_info = state.display_info || Octopus.App.get_display_info()

    %{
      state
      | mode_id: Map.get(config, :mode_id, state.mode_id || @pixel_walk_mode),
        layout_index:
          config
          |> Map.get(:layout_index, state.layout_index || 0)
          |> normalize_index(display_info),
        color_channel: Map.get(config, :color_channel, state.color_channel || :white),
        color: Map.get(config, :color, state.color || "#ffffff"),
        display_info: display_info
    }
  end

  defp apply_layout_index(%State{} = state, layout_index) do
    state = %{state | layout_index: normalize_index(layout_index, state.display_info)}
    render_state(state)
  end

  defp render_state(%State{mode_id: @full_panel_mode} = state) do
    canvas = build_canvas(state)

    case state.color_channel do
      :rgb -> Octopus.App.update_display(canvas, :rgb)
      _ -> Octopus.App.update_display(canvas, :grayscale)
    end

    state
  end

  defp render_state(%State{} = state) do
    canvas = build_canvas(state)
    Octopus.App.update_display(canvas)
    log_pixel(state)
    state
  end

  defp log_pixel(%State{} = state) do
    info = debug_info(state.layout_index)

    Logger.info("""
    Pixie Debug — layout index #{state.layout_index} at (#{info.x}, #{info.y})
      Wiring strip position: #{info.strip}
      Firmware buffer index driving that position: #{info.firmware_index}
      Note which physical LED actually lit up for layout index #{state.layout_index}
    """)
  end

  defp layout_coords(index, width) do
    {rem(index, width), div(index, width)}
  end

  defp normalize_index(index, display_info) when is_number(index) do
    index |> trunc() |> max(0) |> min(max_index(display_info))
  end

  defp max_index(%{panel_width: width, panel_height: height}), do: width * height - 1
  defp max_index(_), do: @max_index

  defp parse_hex_color("#" <> hex) when byte_size(hex) == 6 do
    {r, ""} = Integer.parse(String.slice(hex, 0, 2), 16)
    {g, ""} = Integer.parse(String.slice(hex, 2, 2), 16)
    {b, ""} = Integer.parse(String.slice(hex, 3, 2), 16)
    {r, g, b}
  end

  defp parse_hex_color(_), do: {255, 255, 255}
end
