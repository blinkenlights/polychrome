defmodule Octopus.Apps.Supermario.BadGuy do
  alias __MODULE__
  alias Octopus.Apps.Supermario.Matrix

  @type t :: %__MODULE__{
          x_position: integer(),
          y_position: integer(),
          min_position: integer(),
          max_position: integer(),
          direction: :left | :right
        }
  @color [0, 0, 0]

  defstruct [:x_position, :y_position, :min_position, :max_position, :direction]

  def draw(pixels, %BadGuy{} = bad_guy, current_position) do
    pixels
    |> Matrix.from_list()
    |> set_bad_guy(bad_guy, current_position)
    |> Matrix.to_list()
  end

  #
  defp set_bad_guy(
         pixels,
         %BadGuy{x_position: x_position, y_position: y_position},
         current_position
       )
       when x_position >= current_position do
    put_in(pixels[y_position][x_position - current_position], @color)
  end

  defp set_bad_guy(
         pixels,
         _,
         _
       ),
       do: pixels
end
