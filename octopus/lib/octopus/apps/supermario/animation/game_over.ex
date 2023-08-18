defmodule Octopus.Apps.Supermario.Animation.GameOver do
  alias Octopus.Apps.Supermario.Animation
  alias Octopus.{Canvas, Font}

  # Show Game over moving from left to right
  def new(windows_offset, windows_shown) do
    data = %{
      start_time: Time.utc_now(),
      windows_offset: windows_offset,
      windows_shown: windows_shown
    }

    Animation.new(:game_over, data)
  end

  def draw(%Animation{start_time: start_time, data: data}) do
    font = Font.load("gond")
    diff = Time.diff(Time.utc_now(), start_time, :microsecond)
    offset = Enum.min([Integer.floor_div(diff, div(4_000_000, 9)), 9]) * 8

    canvas =
      "Game Over"
      |> Canvas.from_string(font, 5)

    pixels =
      for x <- 0..(data.windows_shown * 8 - 1),
          y <- 0..7,
          do: {{x + data.windows_offset * 8, y}, Canvas.get_pixel(canvas, {x + offset, y})},
          into: %{}

    %Canvas{canvas | pixels: pixels}
  end
end
