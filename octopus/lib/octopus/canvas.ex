defmodule Octopus.Canvas do
  @moduledoc """
  Provides functions to draw on a canvas. A canvas is a 2D grid of pixels. Each pixel has a color.
  The canvas is used to create frames that can be sent to the mixer.

  ## Example

      iex> canvas = Canvas.new(80, 8)
      iex> canvas = Canvas.put_pixel(canvas, {0, 0}, {255, 255, 255})
      iex> %Octopus.Protobuf.RGBFrame{} = Canvas.to_frame(canvas)

  """

  alias Octopus.Font
  alias Octopus.WebP
  alias Octopus.Protobuf.{RGBFrame}
  alias Octopus.Canvas

  defstruct [:width, :height, :pixels]

  @type coord :: {integer(), integer()}

  @typedoc """
  A color is a tuple of 3 integers between 0 and 255
  """
  @type color :: {non_neg_integer(), non_neg_integer(), non_neg_integer()}

  @type t :: %Canvas{
          width: non_neg_integer(),
          height: non_neg_integer(),
          pixels: %{required(coord()) => color()}
        }

  @doc """
  Creates a new canvas. The canvas is initialized with no pixels set.
  """
  @spec new(non_neg_integer(), non_neg_integer()) :: Canvas.t()
  def new(width, height) do
    %Canvas{
      width: width,
      height: height,
      pixels: %{}
    }
  end

  @doc """
  Creates a new canvas from a webp file.
  The webp file must be located in the priv/webp directory.
  """
  @deprecated "Use Octopus.WebP.load/1 instead"
  @spec from_webp(String.t()) :: Canvas.t()
  def from_webp(name) do
    WebP.load(name)
  end

  @doc """
  Encodes the canvas as a webp file.
  """
  @spec to_webp(Octopus.Canvas.t()) :: binary()
  def to_webp(%Canvas{} = canvas) do
    rgb_pixels =
      for y <- 0..(canvas.height - 1),
          x <- 0..(canvas.width - 1),
          {r, g, b} <- Octopus.Canvas.get_pixel(canvas, {x, y}),
          do: [r, g, b]

    WebP.encode_rgb(List.flatten(rgb_pixels), canvas.width, canvas.height)
  end

  @doc """
  Clears the canvas.
  """
  @spec clear(Canvas.t()) :: Canvas.t()
  def clear(%Canvas{} = canvas) do
    %Canvas{canvas | pixels: %{}}
  end

  @doc """
  Clears a rectangular subsection of the canvas
  """
  def clear_rect(%Canvas{} = canvas, {x1, y1}, {x2, y2}) do
    pixels =
      for x <- x1..x2, y <- y1..y2, reduce: canvas.pixels do
        acc -> Map.delete(acc, {x, y})
      end

    %Canvas{canvas | pixels: pixels}
  end

  @doc """
  Sets the color of the pixel at the given position.
  """
  @spec put_pixel(Canvas.t(), coord(), color()) :: Canvas.t()
  def put_pixel(%Canvas{pixels: pixels} = canvas, {x, y}, {r, g, b}) do
    pixels = Map.put(pixels, {x, y}, {r, g, b})
    %Canvas{canvas | pixels: pixels}
  end

  def put_pixel(%Canvas{}, _, color), do: raise("Invalid color #{inspect(color)}")

  @doc """
  Returns the pixel at the given position.
  If the position is outside the canvas `{0, 0, 0}` is returned.
  """
  @spec get_pixel(Canvas.t(), coord()) :: color()
  def get_pixel(%Canvas{pixels: pixels}, {x, y}) do
    Map.get(pixels, {x, y}, {0, 0, 0})
  end

  @doc """
  Renders a string onto the canvas using the given font and variant.
  """
  @spec put_string(Canvas.t(), coord(), String.t() | charlist(), Font.t(), non_neg_integer()) ::
          Canvas.t()
  def put_string(canvas, pos, string, font, variant \\ 0)

  def put_string(%Canvas{} = canvas, {x, y}, string, %Font{} = font, variant)
      when is_binary(string) do
    chars = string |> String.to_charlist()
    put_string(canvas, {x, y}, chars, font, variant)
  end

  def put_string(%Canvas{} = canvas, {x, y}, chars, %Font{} = font, variant)
      when is_list(chars) do
    chars
    |> Enum.with_index()
    |> Enum.reduce(canvas, fn {char, i}, acc ->
      Font.draw_char(font, char, variant, acc, {x + i * 8, y})
    end)
  end

  @doc """
  Creates a canvas that fits the given string.
  The string is rendered using the given font and variant.
  """
  @spec from_string(String.t() | charlist(), Font.t(), non_neg_integer()) :: Canvas.t()
  def from_string(string, font, variant \\ 0)

  def from_string(string, %Font{} = font, variant) when is_binary(string) do
    string
    |> String.to_charlist()
    |> from_string(font, variant)
  end

  def from_string(chars, %Font{} = font, variant) when is_list(chars) do
    chars
    |> Enum.with_index()
    |> Enum.reduce(Canvas.new(length(chars) * 8, 8), fn {char, i}, acc ->
      Font.draw_char(font, char, variant, acc, {i * 8, 0})
    end)
  end

  @window_width 8
  @window_gap 16
  @window_and_gap @window_gap + @window_width

  def to_frame(%Canvas{width: width, height: height} = canvas, opts \\ []) do
    window_width = if Keyword.get(opts, :drop, false), do: @window_and_gap, else: @window_width
    easing_interval = Keyword.get(opts, :easing_interval, 0)

    data =
      for window <- 0..(div(width, window_width) - 1),
          y <- 0..(height - 1),
          x <- 0..7,
          {r, g, b} = get_pixel(canvas, {window * window_width + x, y}),
          do: [r, g, b]

    %RGBFrame{data: data |> IO.iodata_to_binary(), easing_interval: easing_interval}
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
  Flips the canvas horizontally or vertically.
  """
  @spec flip(Canvas.t(), :horizontal | :vertical) :: Canvas.t()
  def flip(%Canvas{width: width} = canvas, :horizontal) do
    pixels = canvas.pixels |> Enum.map(fn {{x, y}, color} -> {{width - x - 1, y}, color} end)

    %Canvas{canvas | pixels: pixels}
  end

  def flip(%Canvas{height: height} = canvas, :vertical) do
    pixels = canvas.pixels |> Enum.map(fn {{x, y}, color} -> {{x, height - y - 1}, color} end)

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
  Joins the canvases by appending the second canvas to right or the bottom (when vertical is true).

  ## Options
  * `:direction` - `:vertical` or `:horizontal` [default: `:horizontal`]

  """
  def join(%Canvas{} = canvas1, %Canvas{} = canvas2, opts \\ []) do
    direction = Keyword.get(opts, :direction, :horizontal)

    pixels =
      Enum.reduce(canvas2.pixels, canvas1.pixels, fn {{x, y}, color}, pixels ->
        case direction do
          :horizontal -> Map.put(pixels, {x + canvas1.width, y}, color)
          :vertical -> Map.put(pixels, {x, y + canvas1.height}, color)
        end
      end)

    {width, height} =
      case direction do
        :horizontal -> {canvas1.width + canvas2.width, max(canvas1.height, canvas2.height)}
        :vertical -> {max(canvas1.width, canvas2.width), canvas1.height + canvas2.height}
      end

    %Canvas{canvas1 | width: width, height: height, pixels: pixels}
  end

  @doc """
  Overlays the the second canvas over the first one.

  ## Options
  * `:offset` - Format: `{x, y}` [default: `{0, 0}`]
  * `:transparency` - Treat undefined pixels as transparent. [default: `true`]
  """

  def overlay(%Canvas{} = canvas1, %Canvas{} = canvas2, opts \\ []) do
    {dx, dy} = Keyword.get(opts, :offset, {0, 0})

    canvas1 =
      if Keyword.get(opts, :transparency, true) do
        canvas1
      else
        Canvas.clear_rect(canvas1, {dx, dy}, {dx + canvas2.width - 1, dy + canvas2.height - 1})
      end

    pixels =
      Enum.reduce(canvas2.pixels, canvas1.pixels, fn {{x, y}, color}, pixels ->
        Map.put(pixels, {x + dx, y + dy}, color)
      end)

    %Canvas{
      canvas1
      | width: max(canvas1.width, canvas2.width),
        height: max(canvas1.height, canvas2.height),
        pixels: pixels
    }
  end

  @doc """
  Returns a rectangular subsection of the canvas.
  """
  def cut(%Canvas{} = canvas, {x1, y1}, {x2, y2}) when x2 > x1 and y2 > y1 do
    width = x2 - x1 + 1
    height = y2 - y1 + 1

    pixels =
      for x <- x1..x2,
          y <- y1..y2,
          do: {{x - x1, y - y1}, Canvas.get_pixel(canvas, {x, y})},
          into: %{}

    %Canvas{canvas | width: width, height: height, pixels: pixels}
  end

  def flip_horizontal(%Canvas{} = canvas) do
    pixels =
      for x <- 0..(canvas.width - 1),
          y <- 0..(canvas.height - 1),
          do: {{x, y}, Canvas.get_pixel(canvas, {canvas.width - 1 - x, y})},
          into: %{}

    %Canvas{canvas | pixels: pixels}
  end

  def flip_vertical(%Canvas{} = canvas) do
    pixels =
      for x <- 0..(canvas.width - 1),
          y <- 0..(canvas.height - 1),
          do: {{x, y}, Canvas.get_pixel(canvas, {x, canvas.height - 1 - y})},
          into: %{}

    %Canvas{canvas | pixels: pixels}
  end

  @doc """
  Create SVG representation of the canvas by rendering the pixels
  left to right, top to bottom in lines
  """
  def to_svg(canvas, opts \\ []) do
    opts =
      Keyword.validate!(opts,
        width: canvas.width,
        height: canvas.height
      )

    svg_header = """
          <svg
            xmlns="http://www.w3.org/2000/svg"
            width="#{opts[:width]}px" height="#{opts[:height]}px"
            viewbox="0 0 #{canvas.width} #{canvas.height}">
    """

    svg_footer = """
          </svg>
    """

    # traverse pixels left to right, top to bottom
    svg_pixels =
      for y <- 0..(canvas.height - 1),
          x <- 0..(canvas.width - 1),
          {r, g, b} = Canvas.get_pixel(canvas, {x, y}) do
        """
        <rect x="#{x}" y="#{y}" fill="rgb(#{r},#{g},#{b})" width="1" height="1" />
        """
      end

    svg_header <> Enum.join(svg_pixels) <> svg_footer
  end
end

defimpl Collectable, for: Octopus.Canvas do
  alias Octopus.Canvas

  def into(canvas) do
    collector_fun = fn
      canvas_acc, {:cont, {{x, y}, color}} ->
        Canvas.put_pixel(canvas_acc, {x, y}, color)

      canvas_acc, :done ->
        canvas_acc

      _canvas_acc, :halt ->
        :ok
    end

    {canvas, collector_fun}
  end
end

defimpl Inspect, for: Octopus.Canvas do
  alias Octopus.Canvas

  @doc """
  Inspect implementation for printing out Canvas objects on the iex command line
  """
  def inspect(canvas, _opts) do
    default_color = IO.ANSI.default_color()

    # traverse pixels left to right, top to bottom
    delimiter = default_color <> "+" <> String.duplicate("--", canvas.width) <> "+\n"

    lines =
      for y <- 0..(canvas.height - 1) do
        line =
          for x <- 0..(canvas.width - 1) do
            {r, g, b} = Canvas.get_pixel(canvas, {x, y})
            IO.ANSI.color(convert_color_rgb_to_ansi(r, g, b)) <> "\u2588\u2588"
          end
          |> List.to_string()

        default_color <> "|" <> line <> default_color <> "|\n"
      end

    delimiter <> Enum.join(lines) <> delimiter
  end

  def convert_color_rgb_to_ansi(r, g, b) do
    cond do
      r == g and g == b ->
        cond do
          r < 8 -> 16
          r > 248 -> 231
          true -> round((r - 8) / 247 * 24) + 232
        end

      true ->
        16 + 36 * round(r / 255 * 5) + 6 * round(g / 255 * 5) + round(b / 255 * 5)
    end
  end
end
