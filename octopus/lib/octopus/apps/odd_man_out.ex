defmodule Octopus.Apps.OddManOut do
  alias Octopus.Protobuf.InputEvent
  alias Octopus.Canvas
  alias Octopus.Sprite

  use Octopus.App

  @fps 60
  @frame_time_ms trunc(1000 / @fps)

  defmodule Round do
    defstruct [:correct_index, :sprites, :start]

    def new(correct_index, sprites, start),
      do: %Round{correct_index: correct_index, sprites: sprites, start: start}
  end

  defmodule State do
    defstruct [:sprite_sheets, :round, :t, round_time: 5, score: 0]
  end

  def name, do: "Odd Man Out"

  defp start(%State{} = state) do
    first_round =
      Round.new(2, for(i <- 0..2, do: Sprite.load(state.sprite_sheets.menu, i)), state.t)

    %State{
      state
      | round: first_round,
        score: 0
    }
  end

  defp next_round(%State{} = state) do
    max_sprite_number = 80

    rand1 = :rand.uniform(max_sprite_number - 1)

    correct_sprite = Sprite.load(state.sprite_sheets.figures, rand1)
    incorrect_sprite = Sprite.load(state.sprite_sheets.figures, rand1 - 1)

    correct_index = :rand.uniform(3) - 1

    sprites =
      [incorrect_sprite, incorrect_sprite]
      |> List.insert_at(correct_index, correct_sprite)

    Round.new(correct_index, sprites, state.t)
    |> IO.inspect()
  end

  defp selected(%State{round: %Round{correct_index: index}} = state, selected_index) do
    cond do
      selected_index == index ->
        IO.inspect(state.score + 1)

        %State{
          state
          | round: next_round(state),
            score: state.score + 1
        }

      true ->
        start(state)
    end
    |> IO.inspect()
    |> display_frame()
  end

  def init(_) do
    sprite_sheets = %{
      menu: "oddmanout-menu",
      figures: "oddmanout-figures",
      timer: "timercircle-sheet"
    }

    state =
      %State{sprite_sheets: sprite_sheets, t: 0}
      |> start()

    :timer.send_interval(@frame_time_ms, :tick)

    {:ok, state}
  end

  defp show_time(%State{t: t, round: %Round{start: start}} = state) do
    time_gone = (t - start) * @frame_time_ms / 1000
    max_sprite_index = 24

    sprite_index =
      case floor(time_gone * max_sprite_index / state.round_time) do
        index when index >= max_sprite_index -> max_sprite_index - 1
        index -> index
      end

    Sprite.load(state.sprite_sheets.timer, sprite_index) |> Canvas.to_rgb()
  end

  defp show_score(%Canvas{} = canvas, _score) do
    canvas
  end

  defp display_frame(%State{round: round} = state) do
    round.sprites
    |> Enum.with_index()
    |> Enum.reduce(Canvas.new(8 * 10, 8), fn {sprite, i}, acc ->
      acc |> Canvas.overlay(sprite |> Canvas.to_rgb(), offset: {8 * (3 + i), 0})
    end)
    |> Canvas.overlay(show_time(state), offset: {8 * 2, 0})
    |> show_score(state.score)
    #    |> IO.inspect()
    |> Canvas.to_frame()
    |> send_frame()

    state
  end

  defp tick(state) do
    display_frame(state)
  end

  def handle_info(:tick, %State{} = state) do
    new_state = tick(%State{state | t: state.t + 1})
    {:noreply, new_state}
  end

  def handle_input(%InputEvent{type: :BUTTON_1, value: 1}, state) do
    {:noreply, selected(state, 0)}
  end

  def handle_input(%InputEvent{type: :BUTTON_2, value: 1}, state) do
    {:noreply, selected(state, 1)}
  end

  def handle_input(%InputEvent{type: :BUTTON_3, value: 1}, state) do
    {:noreply, selected(state, 2)}
  end

  def handle_input(%InputEvent{type: _, value: 1}, state) do
    {:noreply, start(state)}
  end

  def handle_input(_event, state) do
    # IO.inspect(event)
    {:noreply, state}
  end
end
