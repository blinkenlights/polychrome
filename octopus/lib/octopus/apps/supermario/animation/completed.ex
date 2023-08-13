defmodule Octopus.Apps.Supermario.Animation.Completed do
  alias Octopus.Apps.Supermario.Animation
  alias Octopus.{Canvas, Font}

  # Show Game over moving from left to right
  def new(windows_offset, windows_shown, score) do
    data = %{
      start_time: Time.utc_now(),
      windows_offset: windows_offset,
      windows_shown: windows_shown,
      score: score
    }

    Animation.new(:completed, data)
  end

  def draw(%Animation{start_time: start_time, data: data}) do
    # all_fonts = Font.list_available() |> Enum.sort()
    font = Font.load("ninj-Ninja Masters (ADK)")
    diff = Time.diff(Time.utc_now(), start_time, :microsecond)
    offset = Enum.min([Integer.floor_div(diff, 150_000), 160])

    canvas =
      "You win! Score: #{data.score}"
      |> Canvas.from_string(font)

    pixels =
      for x <- 0..(data.windows_shown * 8 - 1),
          y <- 0..7,
          do: {{x + data.windows_offset * 8, y}, Canvas.get_pixel(canvas, {x + offset, y})},
          into: %{}

    %Canvas{canvas | pixels: pixels}
  end
end
