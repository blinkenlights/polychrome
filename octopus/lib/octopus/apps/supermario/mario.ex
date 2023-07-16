defmodule Octopus.Apps.Supermario.Mario do
  @moduledoc """
  handles the mario logic, still under heavy development
  """
  alias __MODULE__
  alias Octopus.Apps.Supermario.Matrix

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
    %Mario{x_position: 2, y_position: 6}
  end

  def draw(pixels, %Mario{} = mario) do
    pixels
    |> Matrix.from_list()
    |> set_mario(mario)
    |> Matrix.to_list()
  end

  defp set_mario(matrix, mario) do
    put_in(matrix[mario.y_position][mario.x_position], @colour)
  end
end
