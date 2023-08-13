defmodule Octopus.Apps.Supermario do
  use Octopus.App, category: :game
  require Logger

  alias Octopus.Apps.Supermario.Game
  alias Octopus.{Canvas, Mixer}
  alias Octopus.Protobuf.InputEvent
  alias Octopus.Apps.Input.{ButtonState, JoyState}

  @frame_rate 60
  @frame_time_ms trunc(1000 / @frame_rate)

  # how many windows are we using for the game
  @windows_shown 1

  defmodule State do
    defstruct [:game, :interval, :canvas, :button_state]
  end

  def name(), do: "Supermario"

  def init(_args) do
    game = Game.new(@windows_shown)
    canvas = Canvas.new(80, 8)

    state = %State{
      interval: @frame_time_ms,
      game: game,
      canvas: canvas,
      button_state: ButtonState.new()
    }

    schedule_ticker(state.interval)
    {:ok, state}
  end

  def handle_info(:tick, %State{canvas: canvas, game: game} = state) do
    case Game.tick(game) do
      {:ok, game} ->
        canvas = Canvas.clear(canvas)

        canvas =
          game
          |> Game.draw(canvas)

        canvas |> Canvas.to_frame() |> send_frame()
        {:noreply, %State{state | game: game, canvas: canvas}}

      {:gameover, _game} ->
        Mixer.get_selected_app()
        |> Octopus.AppSupervisor.stop_app()

        {:noreply, nil}
    end
  end

  # ignore input events while mario dies
  def handle_input(
        _,
        %State{game: %Game{state: :mario_dies}} = state
      ),
      do: {:noreply, %State{state | button_state: nil}}

  # also ignore input events between levels
  def handle_input(
        _,
        %State{game: %Game{state: :paused}} = state
      ),
      do: {:noreply, %State{state | button_state: nil}}

  def handle_input(
        %InputEvent{} = event,
        %State{button_state: nil} = state
      ) do
    handle_input(event, %{state | button_state: ButtonState.new()})
  end

  def handle_input(
        %InputEvent{type: type, value: value},
        %State{button_state: button_state} = state
      ) do
    new_button_state = ButtonState.handle_event(button_state, type, value)

    state =
      if ButtonState.button?(new_button_state, :BUTTON_5) do
        game = Game.jump(state.game)
        %{state | game: game}
      else
        state
      end

    state =
      if JoyState.button?(new_button_state.joy1, :r) do
        case Game.move_right(state.game) do
          {:ok, game} ->
            %{state | game: game}

          {:mario_dies, game} ->
            # TODO: show mario dying, then reset game, reduce level by 1, possibly game over
            %{state | game: game}

          {:game_over, game} ->
            %{state | game: game}
        end
      else
        if JoyState.button?(new_button_state.joy1, :l) do
          case Game.move_left(state.game) do
            {:ok, game} ->
              %{state | game: game}
          end
        else
          state
        end
      end

    {:noreply, %{state | button_state: new_button_state}}
  end

  def schedule_ticker(interval) do
    :timer.send_interval(interval, self(), :tick)
  end
end
