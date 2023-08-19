defmodule Octopus.Apps.Blocks do
  use Octopus.App, category: :game
  require Logger

  alias Octopus.Sprite
  alias Octopus.Apps.Blocks
  alias Octopus.Protobuf.InputEvent
  alias Octopus.ButtonState
  alias Octopus.Canvas
  alias Octopus.Font
  alias Blocks.Game

  @frame_rate 60
  @frame_time_ms trunc(1000 / @frame_rate)

  defmodule State do
    defstruct [:game, :button_state, :t, :side]
  end

  def name(), do: "Blocks"

  def icon(), do: Canvas.from_string("T", Font.load("robot"))

  def init(args) do
    state = %State{
      button_state: ButtonState.new(),
      game: Game.new(args),
      t: 0,
      side: args[:side] || :left
    }

    :timer.send_interval(@frame_time_ms, :tick)
    {:ok, state}
  end

  def handle_info(:tick, %State{} = state) do
    {:noreply, tick(state)}
  end

  def handle_input(
        %InputEvent{type: type, value: value} = _event,
        %State{button_state: bs} = state
      ) do
    {:noreply, %State{state | button_state: bs |> ButtonState.handle_event(type, value)}}
  end

  defp tick(%State{t: t, button_state: %ButtonState{} = bs, side: side} = state) do
    game =
      state.game
      |> Game.tick(
        case side do
          :right -> bs.joy2
          _ -> bs.joy1
        end
      )

    game
    |> Game.render_canvas()
    |> send_canvas()

    %State{state | t: t + 1, game: game}
  end
end
