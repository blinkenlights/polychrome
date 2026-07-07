defmodule Octopus.Apps.PixieDebug do
  use Octopus.App, category: :test

  require Logger

  alias Octopus.Canvas
  alias Octopus.Events.Event.Input, as: InputEvent
  alias Octopus.Hardware
  alias Octopus.Hardware.WireMap
  alias Octopus.Installation

  defmodule State do
    defstruct [:layout_index, :display_info]
  end

  def name(), do: "Pixie Debug"

  def compatible?() do
    installation = Octopus.App.get_installation_info()

    installation.panel_count == 1 and installation.panel_width == 8 and
      installation.panel_height == 8
  end

  def app_init(_args) do
    Octopus.App.configure_display(layout: :gapped_panels)
    Octopus.App.subscribe_to_button_events()

    display_info = Octopus.App.get_display_info()

    state = %State{
      layout_index: 0,
      display_info: display_info
    }

    render(state)
    log_pixel(state)

    {:ok, state}
  end

  def handle_event(%InputEvent{type: :button, action: :press, button: 1}, %State{} = state) do
    last = state.display_info.panel_width * state.display_info.panel_height - 1
    next_index = if state.layout_index >= last, do: 0, else: state.layout_index + 1
    state = %{state | layout_index: next_index}
    render(state)
    log_pixel(state)
    {:noreply, state}
  end

  def handle_event(_event, state), do: {:noreply, state}

  defp render(%State{} = state) do
    canvas = Canvas.new(state.display_info.width, state.display_info.height)
    {x, y} = layout_coords(state.layout_index, state.display_info.panel_width)

    canvas =
      case state.display_info.panel_to_global_coords.(0, x, y) do
        :invalid_panel ->
          canvas

        {gx, gy} ->
          Canvas.put_pixel(canvas, {gx, gy}, {255, 255, 255})
      end

    Octopus.App.update_display(canvas)
  end

  defp log_pixel(%State{} = state) do
    slot = hd(Installation.panel_slots())
    controller = Hardware.fetch!(slot.controller_id)
    wiring = Hardware.fetch_wiring!(slot.wiring_id)
    layout = Installation.panel_layout()
    {x, y} = layout_coords(state.layout_index, elem(layout, 0))

    strip = WireMap.layout_to_strip(state.layout_index, wiring, elem(layout, 0), elem(layout, 1))

    firmware_index =
      WireMap.firmware_index_for_layout(x, y, layout, wiring, controller)

    Logger.info("""
    Pixie Debug — layout index #{state.layout_index} at (#{x}, #{y})
      Wiring strip position: #{strip}
      Firmware buffer index driving that position: #{firmware_index}
      Note which physical LED actually lit up for layout index #{state.layout_index}
    """)
  end

  defp layout_coords(index, width) do
    {rem(index, width), div(index, width)}
  end
end
