defmodule Octopus.Apps.Supermario.Mario do
  @moduledoc """
  handles the mario logic, still under heavy development
  """
  alias __MODULE__
  alias Octopus.Apps.Supermario.Matrix

  @start_position_x 3
  @jump_interval_ms 5_000
  @colour [216, 40, 0]
  @type t :: %__MODULE__{
          x_position: integer(),
          y_position: integer(),
          jumping: boolean(),
          jumped_at: Time.t()
        }
  defstruct [
    :x_position,
    :y_position,
    :jumping,
    :jumped_at
  ]

  def new do
    %Mario{x_position: @start_position_x, y_position: 6, jumping: false, jumped_at: nil}
  end

  def draw(pixels, %Mario{} = mario) do
    pixels
    |> Matrix.from_list()
    |> set_mario(mario)
    |> Matrix.to_list()
  end

  # FIXME movement (also jumping) can result to a gameover, check here or in game?!
  def move_left(%Mario{x_position: 0} = mario), do: mario

  def move_left(%Mario{} = mario) do
    IO.inspect("move left #{mario.x_position}")
    %Mario{mario | x_position: mario.x_position - 1}
  end

  def move_right(%Mario{} = mario) do
    %Mario{mario | x_position: mario.x_position + 1}
  end

  def jump(%Mario{jumping: false} = mario) do
    %Mario{mario | y_position: mario.y_position - 1, jumping: true, jumped_at: Time.utc_now()}
  end

  def jump(%Mario{jumping: true, jumped_at: jumped_at} = mario) do
    now = Time.utc_now()
    # y position 2 is arbitrary, just to prevent jumping into the sky
    if Time.diff(now, jumped_at, :microsecond) > @jump_interval_ms && mario.y_position > 2 do
      %Mario{mario | y_position: mario.y_position - 1, jumping: true, jumped_at: Time.utc_now()}
    else
      mario
    end
  end

  def update(%Mario{jumping: true, y_position: y_position, jumped_at: jumped_at} = mario) do
    now = Time.utc_now()
    # jump a second pixel after a while
    # TODO: use another constant, jump_interval_ms is used to prevent a second jump within a short time
    if Time.diff(now, jumped_at, :microsecond) > @jump_interval_ms do
      %Mario{mario | y_position: y_position - 1, jumping: false, jumped_at: nil}
    else
      mario
    end
  end

  def update(%Mario{y_position: y_position} = mario) do
    mario =
      if can_fall?(mario) do
        %Mario{mario | y_position: y_position + 1}
      else
        mario
      end

    %Mario{mario | jumping: false, jumped_at: nil}
  end

  # very simple implementation wether maria can fall or not
  defp can_fall?(%Mario{y_position: y_position}) do
    y_position < 6
  end

  def start_position_x, do: @start_position_x

  defp set_mario(matrix, mario) do
    put_in(matrix[mario.y_position][mario.x_position], @colour)
  end
end
