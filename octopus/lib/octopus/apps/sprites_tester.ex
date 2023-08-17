defmodule Octopus.Apps.SpritesTester do
  use Octopus.App, category: :test
  require Logger

  alias Octopus.{Sprite, Canvas}
  alias Octopus.Protobuf.{InputEvent}

  defmodule State do
    defstruct [:index]
  end

  @sprite_sheet Sprite.list_sprite_sheets() |> hd()

  def name(), do: "Sprite Tester"

  def init(_args) do
    state = %State{
      index: 0
    }

    :timer.send_interval(100, :tick)

    {:ok, state}
  end

  def handle_info(:tick, %State{} = state) do
    #    IO.inspect(state.index)

    Sprite.load(@sprite_sheet, state.index)
    |> Canvas.to_frame()
    |> send_frame()

    {:noreply, state}
  end

  def handle_input(%InputEvent{type: :BUTTON_1, value: 1}, state) do
    state = %State{state | index: rem(state.index + 1, 256)}
    {:noreply, state}
  end

  def handle_input(%InputEvent{type: :BUTTON_2, value: 1}, state) do
    state = %State{state | index: max(state.index - 1, 0)}
    {:noreply, state}
  end
end
