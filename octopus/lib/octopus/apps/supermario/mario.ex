defmodule Octopus.Apps.Supermario.Mario do
  @moduledoc """
  handles the mario logic, still under heavy development
  """
  alias __MODULE__
  alias Octopus.Apps.Supermario.Matrix

  @start_position_x 3
  @colour [216, 40, 0]
  @type t :: %__MODULE__{
          x_position: integer(),
          y_position: integer()
        }
  defstruct [
    :x_position,
    :y_position
  ]

  def new do
    %Mario{x_position: @start_position_x, y_position: 6}
  end

  def draw(pixels, %Mario{} = mario) do
    pixels
    |> Matrix.from_list()
    |> set_mario(mario)
    |> Matrix.to_list()
  end

  def move_left(%Mario{x_position: 0} = mario), do: mario

  def move_left(%Mario{} = mario) do
    IO.inspect("move left #{mario.x_position}")
    %Mario{mario | x_position: mario.x_position - 1}
  end

  def move_right(%Mario{} = mario) do
    %Mario{mario | x_position: mario.x_position + 1}
  end

  def start_position_x, do: @start_position_x

  defp set_mario(matrix, mario) do
    put_in(matrix[mario.y_position][mario.x_position], @colour)
  end
end
