alias Octopus.{
  Protobuf,
  AppSupervisor,
  AppRegistry,
  Mixer,
  Apps,
  Font,
  Broadcaster,
  Transitions,
  Canvas,
  Sprite,
  GameScheduler,
  Installation,
  Apps.PixelFun,
  Canvas
}

IEx.configure(inspect: [limit: :infinity, printable_limit: :infinity])
Logger.configure(level: :info)

mario =
  if Code.ensure_loaded?(Octopus) do
    Sprite.load("256-characters-original", 0)
  else
    nil
  end

show_font =
  if Code.ensure_loaded?(Font) do
    fn font_name ->
      0..255
      |> Enum.map(fn i ->
        string = to_string([i])
        {string, Canvas.new(8, 8) |> Canvas.put_string({0, 0}, string, Font.load(font_name))}
      end)
      |> Enum.filter(fn {_i, canvas} ->
        canvas.pixels != Canvas.fill(Canvas.new(8, 8), {0, 0, 0}).pixels
      end)
    end
  else
    nil
  end

pixel_fun =
  if Code.ensure_loaded?(PixelFun) do
    fn canvas, expr, duration, color_a, color_b ->
      fps = 60
      num_frames = trunc(duration * fps)

      {:ok, expr} = PixelFun.Program.parse(expr)

      for frame <- 0..(num_frames - 1) do
        for y <- 0..(canvas.height - 1),
            x <- 0..(canvas.width - 1),
            i = x + y * canvas.width,
            into: canvas do
          t = frame * (1 / fps)
          {{x, y}, PixelFun.pixels(expr, x, y, i, t, color_a, color_b)}
        end
      end
    end
  else
    nil
  end

render_pixel_fun_webp_animation =
  if Code.ensure_loaded?(PixelFun) do
    fn canvas, expr, duration, color_a, color_b ->
      pixel_fun.(canvas, expr, duration, color_a, color_b)
      |> Enum.with_index()
      |> Enum.each(fn {canvas, frame} ->
        canvas
        |> Canvas.to_webp()
        |> then(&File.write!("pixel_fun_#{frame}.webp", &1))
      end)
    end
  else
    nil
  end
