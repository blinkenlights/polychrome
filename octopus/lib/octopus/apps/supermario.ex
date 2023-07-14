defmodule Octopus.Apps.Supermario do
  use Octopus.App
  require Logger

  alias Octopus.Apps.Supermario.Game
  alias Octopus.Canvas

  @frame_rate 60
  @frame_time_ms trunc(1000 / @frame_rate)

  # how many windows are we using for the game
  @windows_shown 4
  # starting from window
  @windows_offset 3

  defmodule State do
    defstruct [:game, :interval, :canvas]
  end

  def name(), do: "Supermario"

  def init(_args) do
    game = Game.new(@windows_shown)
    canvas = Canvas.new(80, 8)

    state = %State{
      interval: @frame_time_ms,
      game: game,
      canvas: canvas
    }

    schedule_ticker(state.interval)
    {:ok, state}
  end

  def handle_info(:tick, %State{canvas: canvas, game: game} = state) do
    canvas = Canvas.clear(canvas)

    game =
      case Game.tick(game) do
        {:ok, game} ->
          game

          # {:game_over, game} ->
          #   game
          # FIXME: show end screen
      end

    canvas = Game.current_pixels(game) |> fill_canvas(canvas)
    canvas |> Canvas.to_frame() |> send_frame()
    schedule_ticker(state.interval)
    {:noreply, %State{state | game: game, canvas: canvas}}
  end

  def handle_info(:move, state) do
    # handles joystick input
    {:noreply, state}
  end

  def schedule_ticker(interval) do
    :timer.send_interval(interval, self(), :tick)
  end

  def fill_canvas(visible_level_pixels, canvas) do
    {canvas, _} =
      Enum.reduce(visible_level_pixels, {canvas, 0}, fn row, {canvas, y} ->
        {canvas, _, y} =
          Enum.reduce(row, {canvas, 0, y}, fn pixel, {canvas, x, y} ->
            canvas =
              Canvas.put_pixel(
                canvas,
                {x + @windows_offset * 8, y},
                pixel |> :binary.bin_to_list() |> Enum.slice(0, 3)
              )

            {canvas, x + 1, y}
          end)

        {canvas, y + 1}
      end)

    canvas
  end
end
