defmodule Octopus.Apps.SampleApp do
  use Octopus.App, category: :test
  require Logger

  alias Octopus.Canvas
  alias Octopus.Events.Event.Input, as: InputEvent

  defmodule State do
    defstruct [:index, :color, :canvas, :display_info]
  end

  @fps 60

  def name(), do: "Sample"

  def app_init(_args) do
    # Configure display using new unified API - gapped layout (was VirtualMatrix :gapped_panels)
    Octopus.App.configure_display(layout: :gapped_panels)

    # Get display info instead of VirtualMatrix
    display_info = Octopus.App.get_display_info()
    canvas = Canvas.new(display_info.width, display_info.height)

    state = %State{
      index: 0,
      canvas: canvas,
      display_info: display_info
    }

    # Use new unified display API instead of Canvas.to_frame() |> VirtualMatrix.send_frame()
    Octopus.App.update_display(canvas)

    :timer.send_interval(trunc(1000 / @fps), :tick)

    {:ok, state}
  end

  def handle_info(:tick, %State{} = state) do
    coordinates =
      {rem(state.index, state.display_info.width), trunc(state.index / state.display_info.width)}

    hue_step = 359.0 / (state.display_info.width * state.display_info.height)
    hue = hue_step * state.index

    %Chameleon.RGB{r: r, g: g, b: b} =
      hue
      |> Chameleon.HSL.new(100, 50)
      |> Chameleon.convert(Chameleon.RGB)

    canvas =
      state.canvas
      |> Canvas.clear()
      |> Canvas.put_pixel(coordinates, {r, g, b})

    # Use new unified display API instead of Canvas.to_frame() |> VirtualMatrix.send_frame()
    Octopus.App.update_display(canvas)

    {:noreply,
     %State{
       state
       | canvas: canvas,
         index: rem(state.index + 1, state.display_info.width * state.display_info.height)
     }}
  end

  def handle_event(%InputEvent{type: :button, action: :press, button: 1}, %State{} = state) do
    canvas =
      state.canvas
      |> Canvas.fill_rect(
        {0, 0},
        {state.display_info.width - 1, state.display_info.height - 1},
        {255, 0, 0}
      )

    # Use new unified display API instead of Canvas.to_frame() |> VirtualMatrix.send_frame()
    Octopus.App.update_display(canvas)

    {:noreply, %State{state | canvas: canvas}}
  end

  def handle_event(%InputEvent{type: :button, action: :press, button: 2}, %State{} = state) do
    canvas =
      state.canvas
      |> Canvas.fill_rect(
        {0, 0},
        {state.display_info.width - 1, state.display_info.height - 1},
        {0, 255, 0}
      )

    # Use new unified display API instead of Canvas.to_frame() |> VirtualMatrix.send_frame()
    Octopus.App.update_display(canvas)

    {:noreply, %State{state | canvas: canvas}}
  end

  def handle_event(%InputEvent{}, state) do
    {:noreply, state}
  end

  def handle_event(_event, state) do
    {:noreply, state}
  end
end
