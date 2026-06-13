defmodule Octopus.Apps.Supermario do
  use Octopus.App, category: :game

  alias Octopus.Apps.Supermario.Game
  alias Octopus.Events.Event.Input, as: InputEvent
  alias Octopus.{ButtonState, JoyState}

  @frame_rate 60
  @frame_time_ms trunc(1000 / @frame_rate)

  # how many windows are we using for the game
  @windows_shown 1

  defmodule State do
    defstruct [:game, :interval, :button_state, :args, :side]
  end

  def name(), do: "Supermario"

  def app_init(args \\ %{}) do
    # Configure display using new unified API - adjacent layout (was Canvas.to_frame())
    Octopus.App.configure_display(layout: :adjacent_panels)

    state =
      args
      |> Map.put_new(:windows_shown, @windows_shown)
      |> Map.put_new(:side, :right)
      |> init_state()

    schedule_ticker(state.interval)
    {:ok, state}
  end

  def handle_info(:tick, %State{game: game} = state) do
    case Game.tick(game) do
      {:ok, game} ->
        game
        |> Game.render_canvas()
        |> Octopus.App.update_display()

        {:noreply, %State{state | game: game}}

      {:gameover, _game} ->
        state = init_state(state.args)
        schedule_ticker(state.interval)
        {:noreply, state}
    end
  end

  # ignore input events while mario dies
  def handle_event(
        _,
        %State{game: %Game{state: :mario_dies}} = state
      ),
      do: {:noreply, %State{state | button_state: nil}}

  # also ignore input events between levels
  def handle_event(
        _,
        %State{game: %Game{state: :paused}} = state
      ),
      do: {:noreply, %State{state | button_state: nil}}

  def handle_event(
        %InputEvent{} = event,
        %State{button_state: nil} = state
      ) do
    handle_event(event, %{state | button_state: ButtonState.new()})
  end

  def handle_event(
        %InputEvent{} = event,
        %State{button_state: button_state} = state
      ) do
    new_button_state = ButtonState.handle_event(button_state, event)

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

          # {:mario_dies, game} ->
          # TODO: show mario dying, then reset game, reduce level by 1, possibly game over
          # %{state | game: game}

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

  def handle_event(_event, state) do
    {:noreply, state}
  end

  def schedule_ticker(interval) do
    :timer.send_interval(interval, self(), :tick)
  end

  defp init_state(args) do
    game = Game.new(args)

    %State{
      interval: @frame_time_ms,
      game: game,
      button_state: ButtonState.new(),
      args: args,
      side: args[:side]
    }
  end

  defp joybutton(:right, button_state), do: button_state.joy2
  defp joybutton(:left, button_state), do: button_state.joy1
end
