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
  def new(width, height, palette_name \\ "pico-8.hex") do
    %Canvas{
      width: width,
      height: height,
      pixels: List.duplicate(0, width * height),
      palette: ColorPalette.from_file(palette_name)
    }
  end

  @doc """
  Clears the canvas by setting all pixels to the given color.
  """
  def clear(canvas, color \\ 0) do
    %{canvas | pixels: List.duplicate(color, canvas.width * canvas.height)}
  end

  @doc """
  Sets the color of the pixel at the given position.
  If the position is outside the canvas, the canvas is returned unchanged.
  """
  def put_pixel(canvas, x, y, color) do
    if x < 0 || x >= canvas.width || y < 0 || y >= canvas.height do
      canvas
    else
      index = y * canvas.width + x
      %{canvas | pixels: List.replace_at(canvas.pixels, index, color)}
    end
  end

  @doc """
  Converts the canvas to a frame. The frame contains the canvas pixels in the correct order.
  When the canvas is wider than 80 pixels, we assume that the canvas contains pixels inbetween
  the windows. Those pixels will be omitted.
  """
  def to_frame(%Canvas{pixels: pixels, width: width}) do
    %Frame{data: pixels |> rearrange(width) |> IO.iodata_to_binary()}
  end

  defp rearrange(pixels, width) do
    pixels
    |> Enum.chunk_every(width)
    |> Enum.map(&Enum.chunk_every(&1, @window_size + @gap_size))
    |> transpose()
    |> Enum.map(&Enum.take(&1, @window_size))
    |> remove_gaps(width > @window_size * @windows)
    |> List.flatten()
  end

  defp remove_gaps(pixels, false), do: pixels

  defp remove_gaps(pixels, true) do
    pixels |> Enum.map(fn row -> Enum.map(row, &Enum.take(&1, 8)) end)
  end

  defp transpose(rows) do
    rows
    |> List.zip()
    |> Enum.map(&Tuple.to_list/1)
  end
end
