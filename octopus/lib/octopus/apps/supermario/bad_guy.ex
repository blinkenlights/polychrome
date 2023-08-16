defmodule Octopus.Apps.Supermario.BadGuy do
  alias __MODULE__
  alias Octopus.Apps.Supermario.Matrix

  @type t :: %__MODULE__{
          x_position: integer(),
          y_position: integer(),
          min_position: integer(),
          max_position: integer(),
          direction: :left | :right,
          last_moved_at: Time.t(),
          color: []
        }

  defstruct [
    :x_position,
    :y_position,
    :min_position,
    :max_position,
    :direction,
    :last_moved_at,
    :color
  ]

  def update(%BadGuy{} = bad_guy) do
    if is_nil(bad_guy.last_moved_at) or
         Time.diff(Time.utc_now(), bad_guy.last_moved_at, :millisecond) > 500 do
      move(bad_guy)
    else
      bad_guy
    end
  end

  def move(
        %BadGuy{x_position: x_position, direction: :left, min_position: min_position} = bad_guy
      )
      when x_position <= min_position do
    %BadGuy{
      bad_guy
      | direction: :right,
        x_position: bad_guy.x_position + 1,
        last_moved_at: Time.utc_now()
    }
  end

  def move(%BadGuy{x_position: x_position, direction: :left} = bad_guy) do
    %BadGuy{
      bad_guy
      | x_position: x_position - 1,
        last_moved_at: Time.utc_now()
    }
  end

  def move(
        %BadGuy{x_position: x_position, direction: :right, max_position: max_position} = bad_guy
      )
      when x_position >= max_position do
    %BadGuy{
      bad_guy
      | direction: :left,
        x_position: x_position - 1,
        last_moved_at: Time.utc_now()
    }
  end

  def move(%BadGuy{x_position: x_position, direction: :right} = bad_guy) do
    %BadGuy{
      bad_guy
      | x_position: x_position + 1,
        last_moved_at: Time.utc_now()
    }
  end

  def on_position?(
        %BadGuy{x_position: x_position, y_position: y_position},
        x_position_to_ask,
        y_position_to_ask
      )
      when x_position == x_position_to_ask and y_position == y_position_to_ask,
      do: true

  def on_position?(_, _, _), do: false

  def draw(pixels, %BadGuy{} = bad_guy, current_position, width) do
    pixels
    |> Matrix.from_list()
    |> set_bad_guy(bad_guy, current_position, width)
    |> Matrix.to_list()
  end

  defp set_bad_guy(
         pixels,
         %BadGuy{x_position: x_position, y_position: y_position, color: color},
         current_position,
         width
       )
       when x_position >= current_position and x_position < current_position + width do
    put_in(pixels[y_position][x_position - current_position], color)
  end

  defp set_bad_guy(
         pixels,
         _,
         _,
         _
       ),
       do: pixels
end
