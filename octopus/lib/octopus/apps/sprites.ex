defmodule Octopus.Apps.Sprites do
  use Octopus.App
  require Logger

  alias Octopus.{Sprite, Canvas}
  alias Octopus.Protobuf.{InputEvent}

  defmodule State do
    defstruct [:canvas, :direction, :animantion_start, :index]
  end

  @sprite_sheet Sprite.list_sprite_sheets() |> hd()
  @animation_duration 1000

  def name(), do: "Sprites"

  def init(_args) do
    state = %State{index: 0} |> next_sprite()

    :timer.send_interval(25, :tick)

    {:ok, state}
  end

  def handle_info(:tick, %State{} = state) do
    animation_end = state.animantion_start + @animation_duration

    max_translate = state.canvas.height - 8

    translate =
      case System.os_time(:millisecond) do
        now when now >= animation_end ->
          max_translate

        now ->
          ((animation_end - now) / @animation_duration)
          |> Easing.cubic_in_out()
          |> then(fn progress -> max_translate - round(progress * max_translate) end)
      end

    state.canvas
    |> Canvas.cut({0, translate}, {8, 8 + translate})
    |> Canvas.to_frame()
    |> send_frame()

    {:noreply, state}
  end

  def handle_input(%InputEvent{button: :BUTTON_1, pressed: true}, state) do
    {:noreply, next_sprite(state)}
  end

  def next_sprite(%State{} = state) do
    next_index = rem(state.index + 1, 256)
    current_sprite = Sprite.load(@sprite_sheet, state.index)
    separator = Canvas.new(8, 3, current_sprite.palette)
    next_sprite = Sprite.load(@sprite_sheet, next_index)

    %State{
      state
      | animantion_start: System.os_time(:millisecond),
        index: next_index,
        canvas:
          Canvas.join(current_sprite, separator, true)
          |> Canvas.join(next_sprite, true)
    }
  end
end
