alias Octopus.{
  Protobuf,
  AppSupervisor,
  AppRegistry,
  Mixer,
  ColorPalette,
  Apps,
  Font,
  Broadcaster,
  Transitions,
  Canvas,
  Sprite
}

IEx.configure(inspect: [limit: :infinity])
Logger.configure(level: :info)

mario = Sprite.load("256-characters-original", 0, :rgb)

