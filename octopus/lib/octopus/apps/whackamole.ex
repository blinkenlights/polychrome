defmodule Octopus.Apps.Whackamole do
  use Octopus.App, category: :game
  require Logger

  alias Octopus.Protobuf.InputEvent
  alias Octopus.ButtonState
  alias Octopus.Canvas
  alias Octopus.Font
  alias Octopus.Apps.Whackamole.Game

  @tick_every_ms 100

  defmodule State do
    defstruct [:game]
  end

  def name(), do: "Whackamole"

  def icon(), do: Canvas.from_string("W", Font.load("cshk-Captain Sky Hawk (RARE)"), 3)

  def init(_) do
    state = %State{game: Game.new()}

    :timer.send_interval(@tick_every_ms, :tick)
    {:ok, state}
  end

  def handle_info(:tick, %State{} = state) do
    game = Game.tick(state.game)

    {:noreply, %State{state | game: game}}
  end

  @whack_buttons [
    :BUTTON_1,
    :BUTTON_2,
    :BUTTON_3,
    :BUTTON_4,
    :BUTTON_5,
    :BUTTON_6,
    :BUTTON_7,
    :BUTTON_8,
    :BUTTON_9,
    :BUTTON_10
  ]
  def handle_input(%InputEvent{type: button, value: 1}, %State{} = state)
      when button in @whack_buttons do
    button_number = String.to_integer(String.split(to_string(button), "_") |> List.last()) - 1

    game = Game.whack(state.game, button_number)

    {:noreply, %State{state | game: game}}
  end

  def handle_input(%InputEvent{}, %State{} = state) do
    {:noreply, state}
  end
end
