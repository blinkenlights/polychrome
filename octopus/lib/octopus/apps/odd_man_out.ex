defmodule Octopus.Apps.OddManOut do
  alias Octopus.Protobuf.InputEvent
  alias Octopus.Canvas
  alias Octopus.Sprite

  use Octopus.App

  @fps 1
  @frame_time_ms trunc(1000 / @fps)

  defmodule State do
    defstruct [
      :canvas,
      :sprite_sheets,
      :t
    ]
  end

  def name, do: "Odd Man Out"

  def init(_) do
    state = %State{
      canvas: [Canvas.new(8, 8), Canvas.new(8, 8), Canvas.new(8, 8)],
      sprite_sheets: %{
        menu: "oddmanout-menu",
        figures: "oddmanout-figures"
      },
      t: 0
    }

    :timer.send_interval(@frame_time_ms, :tick)

    {:ok, state}
  end

  defp show_current_tiles(%State{} = state) do
    c1 = Sprite.load(state.sprite_sheets.menu, 0)
    c2 = Sprite.load(state.sprite_sheets.menu, 1)
    c3 = Sprite.load(state.sprite_sheets.menu, 2)
    %State{state | canvas: [c1, c2, c3]}
  end

  defp display_frame(%State{canvas: [c1, c2, c3]}) do
    Canvas.new(8 * 10, 8, c1.palette)
    |> Canvas.overlay(c1, offset: {8 * 3, 0})
    |> Canvas.overlay(c2, offset: {8 * 4, 0})
    |> Canvas.overlay(c3, offset: {8 * 5, 0})
    |> IO.inspect()
    |> Canvas.to_frame()
    |> send_frame()
  end

  defp tick(state) do
    state = show_current_tiles(state)
    display_frame(state)
    state
  end

  def handle_info(:tick, %State{} = state) do
    new_state = tick(%State{state | t: state.t + 1})
    {:noreply, new_state}
  end

  def handle_input(%InputEvent{type: :BUTTON_1, value: 1}, state) do
    {:noreply, state}
  end

  def handle_input(%InputEvent{type: :BUTTON_2, value: 1}, state) do
    {:noreply, state}
  end

  def handle_input(%InputEvent{type: :BUTTON_3, value: 1}, state) do
    {:noreply, state}
  end

  def handle_input(_event, state) do
    {:noreply, state}
  end
end
