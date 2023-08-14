defmodule Octopus.Apps.Lemmings do
  use Octopus.App, category: :test
  require Logger

  alias Octopus.{Sprite, Canvas}
  alias Octopus.Protobuf.{InputEvent}

  defmodule State do
    defstruct [:index, :walk]
  end

  @sprite_sheet  Path.join(["lemmings","LemmingWalk"])


  def name(), do: "Lemmings"

  def init(_args) do
    state = %State{
      index: 0,
      walk: Sprite.load(@sprite_sheet)
    }

    :timer.send_interval(100, :tick)

    {:ok, state}
  end

  def handle_info(:tick, %State{} = state) do
    state = next(state)

    state.walk
    |> Enum.at(state.index)
    |> Canvas.to_frame()
    |> send_frame()

    {:noreply, state}
  end

  defp next( %State{} = state) do
    %State{
      state | index: rem(state.index + 1, length(state.walk))
    }
  end

  def handle_input(%InputEvent{type: :BUTTON_1, value: 1}, state) do
    state = next(state)
    IO.inspect(state.index)

    {:noreply, state}
  end

  def handle_input(%InputEvent{type: :BUTTON_2, value: 1}, state) do
    state = %State{state | index: max(state.index - 1, 0)}
    IO.inspect(state.index)

    {:noreply, state}
  end

  def handle_input(_,state) do
    {:noreply, state}
  end
end
