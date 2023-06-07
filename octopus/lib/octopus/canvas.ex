defmodule Octopus.Canvas do
  @moduledoc """
  Provides functions to draw on a canvas. A canvas is a 2D grid of pixels. Each pixel has a color.
  The canvas is used to create frames that can be sent to the mixer.

  The canvas can be used with a color palette or with RGB colors.

  ## RGB example

      iex> canvas = Canvas.new(80, 8)
      iex> canvas = Canvas.put_pixel(canvas, {0, 0}, [255, 255, 255])
      iex> %Octopus.Protobuf.Frame{} = Canvas.to_frame(canvas)

  ## Color palette example

      iex> palette = ColorPalette.load("pico-8")
      iex> canvas = Canvas.new(80, 8, palette)
      iex> canvas = Canvas.put_pixel(canvas, {0, 0}, 7)

      iex> canvas = Canvas.new(80, 8, "pico-8")
      iex> canvas = Canvas.put_pixel(canvas, {0, 0}, 7)

  """

  alias Octopus.Protobuf.{Frame, RGBFrame}
  alias Octopus.ColorPalette
  alias Octopus.Canvas

  defstruct [:width, :height, :pixels, :palette]

  @type coord :: {integer(), integer()}
  @type rgb :: list(non_neg_integer())

  @typedoc """
  A color is either a list of 3 integers between 0 and 255
  or a non-negative integer which is an index into a color palette.
  """
  @type color :: non_neg_integer() | rgb()

  @type t :: %Canvas{
          width: non_neg_integer(),
          height: non_neg_integer(),
          pixels: %{required(coord()) => color()},
          palette: ColorPalette.t() | nil
        }

  @doc """
  Creates a new canvas. The canvas is initialized with all pixels set to 0.
  """
  alias Octopus.ColorPalette
  @spec new(non_neg_integer(), non_neg_integer(), nil | binary() | %ColorPalette{}) :: Canvas.t()
  def new(width, height, palette \\ nil)

  def new(width, height, palette) when is_binary(palette) do
    palette = ColorPalette.load(palette)
    new(width, height, palette)
  end

  def new(width, height, palette) do
    %Canvas{
      width: width,
      height: height,
      pixels: %{},
      palette: palette
    }
  end

  @doc """
  Clears the canvas.
  """
  @spec clear(Canvas.t()) :: Canvas.t()
  def clear(%Canvas{} = canvas) do
    %Canvas{canvas | pixels: %{}}
  end

  @doc """
  Sets the color of the pixel at the given position.

  If the canvas has a color palette, the color must be an integer
  that is an index into the palette.

  Otherwise the color must be a list of 3 integers between 0 and 255.
  """
  @spec put_pixel(Canvas.t(), coord(), non_neg_integer() | rgb()) :: Canvas.t()
  def put_pixel(palette, coord, color)

  def put_pixel(%Canvas{palette: %ColorPalette{}} = canvas, {x, y}, color)
      when is_integer(color) do
    pixels = Map.put(canvas.pixels, {x, y}, color)
    %Canvas{canvas | pixels: pixels}
  end

  def put_pixel(%Canvas{palette: nil} = canvas, {x, y}, color) when is_list(color) do
    pixels = Map.put(canvas.pixels, {x, y}, color)
    %Canvas{canvas | pixels: pixels}
  end

  @doc """
  Returns the color of the pixel at the given position.
  If the position is outside the canvas,
  `[0, 0, 0]` is returned for canvases with RGB colors
  and `0` is returned for canvases with a color palette.
  """
  @spec get_pixel(Canvas.t(), coord()) :: color()
  def get_pixel(%Canvas{pixels: pixels, palette: nil}, {x, y}) do
    Map.get(pixels, {x, y}, 0)
  end

  def get_pixel(%Canvas{pixels: pixels}, {x, y}) do
    Map.get(pixels, {x, y}, [0, 0, 0])
  end

  @window_width 8
  @window_gap 16
  @window_and_gap @window_gap + @window_width

  def to_frame(%Canvas{width: width, height: height, palette: palette} = canvas, opts \\ []) do
    window_width = if Keyword.get(opts, :drop, false), do: @window_and_gap, else: @window_width

    pixels =
      for i <- 0..div(width, window_width),
          y <- 0..(height - 1),
          x <- 0..7,
          do: get_pixel(canvas, {i * window_width + x, y})

    case palette do
      nil -> %RGBFrame{data: pixels |> IO.iodata_to_binary()}
      _ -> %Frame{data: pixels, palette: palette}
    end
  end

  @doc """
  Translates the canvas by the given offset.
  Pixels that are moved outside the canvas are discarded.

  If wrap is given pixels that are moved outside the canvas are wrapped around to the other side.
  """
  @spec translate(Canvas.t(), coord(), any()) :: Canvas.t()
  def translate(canvas, delta, wrap \\ false)

  def translate(%Canvas{width: width, height: height} = canvas, {dx, dy}, false) do
    pixels =
      for x <- 0..(width - 1),
          y <- 0..(height - 1),
          new_x = x + dx,
          new_y = y + dy,
          new_x >= 0 && new_x < width,
          new_y >= 0 && new_y < height,
          into: %{},
          do: {{new_x, new_y}, Canvas.get_pixel(canvas, {x, y})}

    %Canvas{canvas | pixels: pixels}
  end

  def translate(%Canvas{width: width, height: height} = canvas, {dx, dy}, _) do
    pixels =
      for x <- 0..(width - 1),
          y <- 0..(height - 1),
          new_x = rem(x + dx, width),
          new_y = rem(y + dy, height),
          into: %{},
          do: {{new_x, new_y}, Canvas.get_pixel(canvas, {x, y})}

    %Canvas{canvas | pixels: pixels}
  end

  @doc """
  Rotates the canvas by 90 degrees.
  """
  @spec rotate(Canvas.t(), :cw | :ccw) :: Canvas.t()
  def rotate(%Canvas{width: width, height: height} = canvas, :cw) do
    pixels =
      for x <- 0..(width - 1),
          y <- 0..(height - 1),
          new_x = y,
          new_y = width - x - 1,
          into: %{},
          do: {{new_x, new_y}, Canvas.get_pixel(canvas, {x, y})}

    %Canvas{canvas | pixels: pixels}
  end

  def rotate(%Canvas{width: width, height: height} = canvas, :ccw) do
    pixels =
      for x <- 0..(width - 1),
          y <- 0..(height - 1),
          new_x = height - y - 1,
          new_y = x,
          into: %{},
          do: {{new_x, new_y}, Canvas.get_pixel(canvas, {x, y})}

    %Canvas{canvas | pixels: pixels}
  end

  @doc """
  Draws a line on the canvas using Bresenham's line algorithm.
  """
  @spec line(Canvas.t(), coord(), coord(), color()) :: Canvas.t()
  def line(canvas, from, to, color)

  def line(%Canvas{} = canvas, {x1, y1}, {x2, y2}, color) do
    dx = abs(x2 - x1)
    sx = if x1 < x2, do: 1, else: -1
    dy = -abs(y2 - y1)
    sy = if y1 < y2, do: 1, else: -1
    err = dx + dy
    count = max(abs(dx), abs(dy))

    draw_line(canvas, {x1, y1}, {dx, dy}, {sx, sy}, err, color, count)
  end

  defp draw_line(canvas, _, _, _, _, _, count) when count < 0, do: canvas

  defp draw_line(canvas, {x, y}, {dx, dy}, {sx, sy}, err, color, count) do
    {offset_x, err_x} = if err * 2 > dy, do: {sx, dy}, else: {0, 0}
    {offset_y, err_y} = if err * 2 < dx, do: {sy, dx}, else: {0, 0}

    canvas
    |> put_pixel({x, y}, color)
    |> draw_line(
      {x + offset_x, y + offset_y},
      {dx, dy},
      {sx, sy},
      err + err_x + err_y,
      color,
      count - 1
    )
  end

  @doc """
  Draws a rectangle on the canvas.
  """
  @spec rect(Canvas.t(), coord(), coord(), color()) :: Canvas.t()
  def rect(%Canvas{} = canvas, {x1, y1}, {x2, y2}, color) do
    canvas
    |> line({x1, y1}, {x2, y1}, color)
    |> line({x2, y1}, {x2, y2}, color)
    |> line({x2, y2}, {x1, y2}, color)
    |> line({x1, y2}, {x1, y1}, color)
  end

  @doc """
  Draws a filled rectangle on the canvas.
  """
  @spec fill_rect(Canvas.t(), coord(), coord(), color()) :: Canvas.t()
  def fill_rect(%Canvas{} = canvas, {x1, y1}, {x2, y2}, color) do
    Enum.reduce(y1..y2, canvas, fn y, canvas ->
      line(canvas, {x1, y}, {x2, y}, color)
    end)
  end

  @doc """
  Draws a polygon on the canvas.
  """
  @spec polygon(Canvas.t(), list(coord()), color()) :: Canvas.t()
  def polygon(%Canvas{} = canvas, points, color) do
    points
    |> Stream.cycle()
    |> Stream.take(length(points) + 1)
    |> Stream.chunk_every(2, 1, :discard)
    |> Enum.to_list()
    |> Enum.reduce(canvas, fn [p1, p2], canvas ->
      line(canvas, p1, p2, color)
    end)
  end

  @doc """
  Joins the canvases by appending the second canvas to right.
  """
  def join(%Canvas{} = canvas1, %Canvas{} = canvas2) do
    if canvas1.palette != canvas2.palette do
      raise ArgumentError, "Can't join canvases with different color palettes"
    end

    pixels =
      Enum.reduce(canvas2.pixels, canvas1.pixels, fn {{x, y}, color}, pixels ->
        Map.put(pixels, {x, y}, color)
      end)

    %Canvas{
      canvas1
      | width: canvas1.width + canvas2.width,
        height: max(canvas1.height, canvas2.height),
        pixels: pixels
    }
  end
end
