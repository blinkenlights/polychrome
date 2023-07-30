defmodule Octopus.Apps.Supermario.Mario do
  @moduledoc """
  handles the mario logic, still under heavy development
  """
  alias __MODULE__
  alias Octopus.Apps.Supermario.{Game, Level, Matrix}

  @start_position_x 3
  @jump_interval_ms 90_000
  @fall_interval_ms 100_000
  @type t :: %__MODULE__{
          x_position: integer(),
          y_position: integer(),
          jumping: boolean(),
          jumped_at: Time.t() | nil,
          falling_since: Time.t() | nil
        }
  defstruct [
    :x_position,
    :y_position,
    :jumping,
    :jumped_at,
    :falling_since
  ]

  def new do
    %Mario{
      x_position: @start_position_x,
      y_position: 6,
      jumping: false,
      jumped_at: nil,
      falling_since: nil
    }
  end

  def draw(pixels, %Mario{} = mario, %Game{} = game) do
    pixels
    |> Matrix.from_list()
    |> set_mario(mario, game)
    |> Matrix.to_list()
  end

  # FIXME movement (also jumping) can result to a gameover, check here or in game?!
  def move_left(%Mario{x_position: 0} = mario, _level), do: mario

  def move_left(%Mario{} = mario, _level) do
    IO.inspect("move left #{mario.x_position}")
    %Mario{mario | x_position: mario.x_position - 1}
  end

  def move_right(%Mario{} = mario, _level) do
    %Mario{mario | x_position: mario.x_position + 1}
  end

  def jump(%Mario{jumping: false} = mario, level) do
    if can_jump?(mario, level) do
      IO.inspect("jumping first #{mario.y_position}")
      %Mario{mario | y_position: mario.y_position - 1, jumping: true, jumped_at: Time.utc_now()}
    else
      mario
    end
  end

  def jump(%Mario{jumping: true, jumped_at: jumped_at} = mario, level) do
    now = Time.utc_now()

    if Time.diff(now, jumped_at, :microsecond) > @jump_interval_ms && can_jump?(mario, level) do
      IO.inspect(
        "jumping second #{mario.y_position}, diff: #{Time.diff(now, jumped_at, :microsecond)}"
      )

      %Mario{mario | y_position: mario.y_position - 1, jumping: true, jumped_at: Time.utc_now()}
    else
      mario
    end
  end

  def update(%Mario{jumping: true, y_position: y_position, jumped_at: jumped_at} = mario, _game) do
    # jump a second pixel after a while
    # TODO: use another constant, jump_interval_ms is used to prevent a second jump within a short time
    if Time.diff(Time.utc_now(), jumped_at, :microsecond) > @jump_interval_ms do
      %Mario{
        mario
        | y_position: y_position - 1,
          jumping: false,
          jumped_at: nil,
          falling_since: Time.utc_now()
      }
    else
      mario
    end
  end

  # falling_since may be nil, when mario was not jumping before but ran over a hole
  # but then we are falling immidiately
  def update(%Mario{y_position: y_position, falling_since: nil} = mario, %Game{} = game) do
    mario =
      if can_fall?(mario, game) do
        IO.inspect("falling #{y_position}")
        %Mario{mario | y_position: y_position + 1, falling_since: Time.utc_now()}
      else
        mario
      end

    mario
  end

  # already falling, check if we can fall further and fall with a delay
  def update(%Mario{y_position: y_position, falling_since: falling_since} = mario, %Game{} = game) do
    if Time.diff(Time.utc_now(), falling_since, :microsecond) > @fall_interval_ms do
      if can_fall?(mario, game) do
        IO.inspect(
          "falling #{y_position}, diff: #{Time.diff(Time.utc_now(), falling_since, :microsecond)}"
        )

        # reset falling timestamp, also next fall should be done with a delay
        %Mario{mario | y_position: y_position + 1, falling_since: Time.utc_now()}
      else
        %Mario{mario | falling_since: nil}
      end
    else
      mario
    end
  end

  # very simple implementation wether mario can fall or not. need to provide a pixel matrix
  defp can_fall?(%Mario{y_position: y_position, x_position: x_position}, %Game{level: level, current_position: current_position}) do
    Level.can_fall?(level, x_position + current_position, y_position)
  end

  # very simple implementation wether maria can jump or not
  defp can_jump?(%Mario{y_position: y_position}, _level) do
    # y position 3 is arbitrary, just to prevent jumping into the sky. need to provide a pixel matrix
    y_position > 3
  end

  def start_position_x, do: @start_position_x

  defp set_mario(matrix, mario, %Game{state: state}) do
    put_in(matrix[mario.y_position][mario.x_position], mario_colour(state))
  end

  defp mario_colour(:mario_dies), do: [66, 44, 23]
  defp mario_colour(_), do: [216, 40, 0]
end
