defmodule Octopus.Apps.Hogg do
  use Octopus.App
  require Logger

  alias Octopus.Apps.Hogg
  alias Octopus.Protobuf.InputEvent
  alias Hogg.Game
  alias Hogg.ButtonState

  @frame_rate 60
  @frame_time_ms trunc(1000 / @frame_rate)

  defmodule State do
    defstruct [:game, :button_state, :t]
  end

  def name(), do: "Hogg"

  def init(_args) do
    state = %State{
      button_state: ButtonState.new(),
      game: Game.new(),
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
    game = state.game |> Game.tick([bs.joy1, bs.joy2])

    game
    |> Game.render_frame()
    |> send_frame()

    %State{state | t: t + 1, game: game}
  end
end
