defmodule Octopus.Apps.Supermario.Animation.MarioDies do
  alias Octopus.Apps.Supermario.Animation
  alias Octopus.Apps.Supermario.Matrix

  @color1 [136, 112, 0]
  @color2 [252, 152, 56]

  # we need to now all current game pixels and the position of mario
  # we rotage marios colour and draw a radial boom effect from marios position
  def new(current_game_pixels, mario_position) do
    data = %{
      current_game_pixels: current_game_pixels,
      mario_position: mario_position
    }

    Animation.new(:mario_dies, data)
  end

  # draw mario blinking and moving up then falling
  def draw(%Animation{start_time: start_time, data: data}) do
    pixel_map = Matrix.from_list(data.current_game_pixels)
    timediff = Time.diff(Time.utc_now(), start_time, :millisecond)

    # time, fn, color
    animations = [
      {100, fn y -> y end, @color2},
      {300, fn y -> max(y - 1, 0) end, @color1},
      {400, fn y -> max(y - 2, 0) end, @color2},
      {500, fn y -> max(y - 3, 0) end, @color1},
      {700, fn y -> max(y - 2, 0) end, @color2},
      {900, fn y -> max(y - 1, 0) end, @color1},
      {1000, fn y -> y end, @color2},
      {1200, fn y -> min(y + 1, 7) end, @color1},
      {1300, fn y -> min(y + 2, 7) end, @color2},
      {1400, fn y -> min(y + 3, 7) end, @color1},
      {1500, fn y -> min(y + 4, 7) end, @color2},
      {1600, fn y -> min(y + 5, 7) end, @color1}
    ]

    {x_position, y_position} = data.mario_position
    {y_function, color} = find_animation(animations, timediff)

    pixel_map = put_in(pixel_map[y_function.(y_position)][x_position], color)

    Matrix.to_list(pixel_map)
  end

  defp find_animation([{timestamp, function, color} | _tail], timediff) when timediff < timestamp,
    do: {function, color}

  defp find_animation([{_timestamp, function, color}], _timediff), do: {function, color}
  defp find_animation([_hd | tail], timediff), do: find_animation(tail, timediff)
end
