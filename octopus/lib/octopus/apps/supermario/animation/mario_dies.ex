defmodule Octopus.Apps.Supermario.Animation.MarioDies do
  alias Octopus.Apps.Supermario.Animation

  # we need to now all current game pixels and the position of mario
  # we rotage marios colour and draw a radial boom effect from marios position
  def new(current_game_pixels, mario_position) do
    data = %{
      current_game_pixels: current_game_pixels,
      mario_position: mario_position
    }

    Animation.new(:mario_dies, data)
  end

  def draw(%Animation{data: data} = animation) do
    # draw(current(pixels))
    # plus(mario)

    data.current_game_pixels
    # |> Mario.draw(mario, colour)
  end
end

# defp mario_colour(:mario_dies), do: [66, 44, 23] ## rotation of colour
