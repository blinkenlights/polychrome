defmodule Octopus.Apps.Snake do
  use Octopus.App, category: :game
  require Logger

  alias Octopus.Sprite
  alias Octopus.Apps.Snake
  alias Octopus.Protobuf.InputEvent
  alias Snake.Game
  alias Snake.ButtonState

  @frame_rate 60
  @frame_time_ms trunc(1000 / @frame_rate)

  defmodule State do
    defstruct [:game, :button_state, :t]
  end

  def name(), do: "Snake"

  def icon(), do: Sprite.load("../images/snake", 0)

  def init(args) do
    state = %State{
      button_state: ButtonState.new(),
      game: Game.new(args),
      t: 0
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

  defp tick(%State{t: t, button_state: %ButtonState{} = bs} = state) do
    game = state.game |> Game.tick(bs.joy1)

    game
    |> Game.render_canvas()
    |> send_canvas()

    %State{state | t: t + 1, game: game}
  end
end
