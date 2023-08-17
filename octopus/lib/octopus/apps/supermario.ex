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
    defstruct [:game, :interval, :canvas, :button_state, :args, :side]
  end

  def name(), do: "Supermario"

  def init(args \\ %{}) do
    state = args
    |> Map.put_new(:windows_shown, @windows_shown)
    |> Map.put_new(:side, :right)
    |> init_state()

    schedule_ticker(state.interval)
    {:ok, state}
  end

  def handle_info(:tick, %State{canvas: canvas, game: game} = state) do
    case Game.tick(game) do
      {:ok, game} ->
        canvas = Canvas.clear(canvas)

        game
        |> Game.draw(canvas)
        |> send_canvas()

        {:noreply, %State{state | game: game, canvas: canvas}}

      {:gameover, _game} ->
        state = init_state(state.args)
        schedule_ticker(state.interval)
        {:noreply, state}
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
      if JoyState.button?(joybutton(state.side, new_button_state), :a) do
        game = Game.jump(state.game)
        %{state | game: game}
      else
        state
      end

    state =
      if JoyState.button?(joybutton(state.side, new_button_state), :r) do
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
        if JoyState.button?(joybutton(state.side, new_button_state), :l) do
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

  defp init_state(args) do
    canvas = Canvas.new(80, 8)
    game = Game.new(args)
    %State{
      interval: @frame_time_ms,
      game: game,
      canvas: canvas,
      button_state: ButtonState.new(),
      args: args,
      side: args[:side]
    }
  end

  defp joybutton(:right, button_state), do: button_state.joy2
  defp joybutton(:left, button_state), do: button_state.joy1
end
