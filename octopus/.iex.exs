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
  Installation
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
