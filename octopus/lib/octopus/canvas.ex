defmodule Octopus.Canvas do
  @moduledoc """
  Provides functions to draw on a canvas. A canvas is a 2D grid of pixels. Each pixel has a color.
  The canvas is used to create frames that can be sent to the mixer.

  ## Example

      iex> canvas = Canvas.new(80, 8)
      iex> canvas = Canvas.put_pixel(canvas, 0, 0, 1)
      iex> %Octopus.Protobuf.Frame{} = Canvas.to_frame(canvas)

  """

  alias Octopus.Protobuf.Frame
  alias Octopus.ColorPalette
  alias Octopus.Canvas

  defstruct [:width, :height, :pixels, :palette]

  @window_size 8
  @gap_size 18
  @windows 10

  @doc """
  Creates a new canvas. The canvas is initialized with all pixels set to 0.
  """
  def new(width, height, palette_name \\ "pico-8") do
    %Canvas{
      width: width,
      height: height,
      pixels: %{},
      palette: ColorPalette.load(palette_name)
    }
  end

  @doc """
  Clears the canvas by setting all pixels to the given color.
  """
  def clear(canvas) do
    %Canvas{canvas | pixels: %{}}
  end

  @doc """
  Sets the color of the pixel at the given position.
  If the position is outside the canvas, the canvas is returned unchanged.
  """
  def put_pixel(canvas, x, y, color) do
    pixels = Map.put(canvas.pixels, {x, y}, color)
    %Canvas{canvas | pixels: pixels}
  end

  @doc """
  Converts the canvas to a frame. The frame contains the canvas pixels in the correct order.
  When the canvas is wider than 80 pixels, we assume that the canvas contains pixels inbetween
  the windows. Those pixels will be omitted.
  """
  def to_frame(%Canvas{pixels: pixels, width: width, palette: palette}) do
    %Frame{data: pixels |> rearrange(width), palette: palette}
  end

  defp rearrange(pixels, width) do
    for x <- 0..(width - 1),
        y <- 0..7,
        into: [],
        do: Map.get(pixels, {x, y}, 0)
  end
end
