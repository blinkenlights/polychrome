defmodule Octopus.Apps.RunningLightsDebug do
  use Octopus.App, category: :test

  require Logger

  alias Octopus.Canvas
  alias Octopus.Events.Event.Input, as: InputEvent
  alias Octopus.Hardware.WireMap

  defmodule State do
    defstruct [:pixel_index, :display_info]
  end

  def name(), do: "Running Lights Debug"

  def compatible?() do
    installation = Octopus.App.get_installation_info()

    installation.panel_count >= 1 and installation.panel_height == 1 and
      installation.panel_width >= 2
  end

  def app_init(_args) do
    Octopus.App.configure_display(layout: :gapped_panels)
    Octopus.App.subscribe_to_button_events()

    display_info = Octopus.App.get_display_info()

    state = %State{
      pixel_index: 0,
      display_info: display_info
    }

    render(state)
    log_pixel(state)

    {:ok, state}
  end

  def handle_event(%InputEvent{type: :button, action: :press, button: 1}, %State{} = state) do
    last = state.display_info.panel_width - 1
    next_index = if state.pixel_index >= last, do: 0, else: state.pixel_index + 1
    state = %{state | pixel_index: next_index}
    render(state)
    log_pixel(state)
    {:noreply, state}
  end

  def handle_event(_event, state), do: {:noreply, state}

  defp render(%State{} = state) do
    canvas = Canvas.new(state.display_info.width, state.display_info.height)

    canvas =
      case state.display_info.panel_to_global_coords.(0, state.pixel_index, 0) do
        :invalid_panel ->
          canvas

        {x, y} ->
          Canvas.put_pixel(canvas, {x, y}, {255, 255, 255})
      end

    Octopus.App.update_display(canvas)
  end

  defp log_pixel(%State{} = state) do
    strip = state.pixel_index
    firmware_index = WireMap.firmware_index_for_strip(strip)

    Logger.info("""
    Running Lights Debug — logical pixel #{state.pixel_index}
      Expected physical strip position (left-to-right): #{strip}
      Firmware buffer index driving that strip position: #{firmware_index}
      Note which physical LED actually lit up for logical #{state.pixel_index}
    """)
  end
end
