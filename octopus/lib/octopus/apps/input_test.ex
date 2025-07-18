defmodule Octopus.Apps.InputTest do
  use Octopus.App, category: :test
  require Logger

  alias Octopus.Events.Event.Input, as: InputEvent
  alias Octopus.InputAdapter
  alias Octopus.Canvas

  @fps 60

  defmodule State do
    defstruct [:display_info]
  end

  def name(), do: "Input Test"

  def app_init(_args) do
    # Configure display using new unified API - adjacent layout
    Octopus.App.configure_display(layout: :adjacent_panels)
    Octopus.App.subscribe_to_button_events()

    # Get display info once and store it
    display_info = Octopus.App.get_display_info()

    state = %State{
      display_info: display_info
    }

    :timer.send_interval(trunc(1000 / @fps), :tick)

    {:ok, state}
  end

  def handle_event(%InputEvent{type: :button, action: :press, button: button} = event, state) do
    Logger.info("Input event: #{inspect(event)}")

    InputAdapter.send_light_event(button, 30_000)

    fill_panel(state, button, {138, 43, 226})

    {:noreply, state}
  end

  def handle_event(%InputEvent{type: :button, action: :release, button: button} = event, state) do
    Logger.info("Input event: #{inspect(event)}")

    InputAdapter.send_light_event(button, 1)

    fill_panel(state, button, {0, 0, 0})

    {:noreply, state}
  end

  def handle_event(%InputEvent{} = event, state) do
    Logger.info("Unhandled input event: #{inspect(event)}")

    {:noreply, state}
  end

  def handle_event(_event, state) do
    {:noreply, state}
  end

  def handle_info(:tick, state) do
    {:noreply, state}
  end

  defp fill_panel(state, button, color)
       when button >= 1 and button <= state.display_info.num_panels do
    panel_width = state.display_info.panel_width
    panel_height = state.display_info.panel_height
    top_left = {(button - 1) * panel_width, 0}
    bottom_right = {elem(top_left, 0) + panel_width - 1, panel_height - 1}

    canvas = Canvas.new(state.display_info.width, state.display_info.height)

    canvas = Canvas.fill_rect(canvas, top_left, bottom_right, color)

    Octopus.App.update_display(canvas)
  end
end
