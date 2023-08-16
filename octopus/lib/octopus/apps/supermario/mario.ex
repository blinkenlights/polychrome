defmodule Octopus.Apps.Supermario.Mario do
  @moduledoc """
  handles the mario logic
  """
  alias __MODULE__
  alias Octopus.Apps.Supermario.{Game, Level, Matrix}

  @start_position_x 3
  @fall_interval_ms 190_000
  @mario_color [235, 13, 16]

  @type t :: %__MODULE__{
          x_position: integer(),
          y_position: integer(),
          jumps: integer(),
          jumped_at: Time.t() | nil,
          falling_since: Time.t() | nil
        }
  defstruct [
    :x_position,
    :y_position,
    :jumps,
    :jumped_at,
    :falling_since
  ]

  def new(start_position_y) do
    %Mario{
      x_position: @start_position_x,
      y_position: start_position_y,
      jumps: 0,
      jumped_at: nil,
      falling_since: nil
    }
  end

  def draw(pixels, %Mario{} = mario) do
    pixels
    |> Matrix.from_list()
    |> set_mario(mario, @mario_color)
    |> Matrix.to_list()
  end

  def move_left(%Mario{x_position: 0} = mario, _level), do: mario

  def move_left(%Mario{} = mario, _level) do
    %Mario{mario | x_position: mario.x_position - 1}
  end

  def move_right(%Mario{} = mario, _level) do
    %Mario{mario | x_position: mario.x_position + 1}
  end

  # first jump. we have to be on the ground, therefor `!can_fall?`
  def jump(%Mario{jumps: 0} = mario, game) do
    if can_jump?(mario, game) and !can_fall?(mario, game) do
      do_jump(mario)
    else
      mario
    end
  end

  # we can jump a second and third time in the air
  def jump(%Mario{jumps: jumps} = mario, game) when jumps == 1 or jumps == 2 do
    if can_jump?(mario, game) do
      do_jump(mario)
    else
      mario
    end
  end

  # in case we would jump more than allowed, check wether we jumped upon something
  # when we cannot fall anymore and we wait a bit, lets jump again
  def jump(%Mario{jumped_at: jumped_at} = mario, game) do
    if !can_fall?(mario, game) &&
         Time.diff(Time.utc_now(), jumped_at, :microsecond) > @fall_interval_ms * 3 do
      do_jump(%Mario{mario | jumps: 0, jumped_at: nil})
    else
      # no third jump should be possible
      mario
    end
  end

  # falling_since may be nil, when mario was not jumping before but ran over a hole
  # but then we are falling immediately
  def fall_if(%Mario{falling_since: nil, jumped_at: nil} = mario, game) do
    if can_fall?(mario, game) do
      {true, do_fall(mario)}
    else
      {false, mario}
    end
  end

  # when mario was jumping before, we have to wait a bit before falling
  def fall_if(%Mario{falling_since: nil, jumped_at: jumped_at} = mario, game) do
    if can_fall?(mario, game) and
         Time.diff(Time.utc_now(), jumped_at, :microsecond) > @fall_interval_ms * 2 do
      {true, do_fall(mario)}
    else
      {false, mario}
    end
  end

  # already falling, check if we can fall further and fall with a delay
  def fall_if(
        %Mario{falling_since: falling_since} = mario,
        %Game{} = game
      ) do
    if Time.diff(Time.utc_now(), falling_since, :microsecond) > @fall_interval_ms do
      if can_fall?(mario, game) do
        # reset falling timestamp, also next fall should be done with a delay
        {true, do_fall(mario)}
      else
        {false, %Mario{mario | falling_since: nil}}
      end
    else
      {false, mario}
    end
  end

  def reset_jumps(%Mario{} = mario) do
    %Mario{mario | jumps: 0, jumped_at: nil}
  end

  defp do_jump(%Mario{y_position: y_position, jumps: jumps} = mario) do
    %Mario{
      mario
      | y_position: y_position - 1,
        falling_since: nil,
        jumps: jumps + 1,
        jumped_at: Time.utc_now()
    }
  end

  defp do_fall(%Mario{y_position: y_position} = mario) do
    %Mario{mario | y_position: y_position + 1, falling_since: Time.utc_now(), jumps: 0}
  end

  def can_fall?(%Mario{y_position: y_position, x_position: x_position}, %Game{
        level: level,
        current_position: current_position
      }) do
    Level.can_fall?(level, x_position + current_position, y_position)
  end

  defp can_jump?(%Mario{y_position: 0}, _), do: false

  defp can_jump?(%Mario{y_position: y_position, x_position: x_position}, %Game{
         level: level,
         current_position: current_position
       }) do
    Level.can_jump?(level, x_position + current_position, y_position)
  end

  def can_move_right?(%Mario{y_position: y_position, x_position: x_position}, %Game{
        level: level,
        current_position: current_position
      }) do
    Level.can_move_right?(level, x_position + current_position, y_position)
  end

  def can_move_left?(%Mario{y_position: y_position, x_position: x_position}, %Game{
        level: level,
        current_position: current_position
      }) do
    Level.can_move_left?(level, x_position + current_position, y_position)
  end

  def start_position_x, do: @start_position_x

  defp set_mario(matrix, mario, mario_color) do
    put_in(matrix[mario.y_position][mario.x_position], mario_color)
  end
end
