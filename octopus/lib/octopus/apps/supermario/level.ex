# matrix with level infos (8 * 120 pixel)
# needs to know position of mario (x,y)
#       where x might be fixed (current position, which moves by a ticker)
# needs to handle ticker and movement of mario
# might end in gameover
# needs to know bonus points when mario jumps on certain points
defmodule Octopus.Apps.Supermario.Level do
  @type t :: %__MODULE__{
          # 8 * 120
          pixels: [],
          # Octopus.Apps.Supermaria.Mario.t(),
          mario: nil,
          ticker: integer(),
          level: integer(),
          points: integer(),
          gameover: boolean()
        }
  defstruct [
    :pixels,
    :mario,
    :ticker,
    :level,
    :points,
    :gameover
  ]

  def build(level) do
    # returns a level with all pixels and all data set
    # TODO: read png and init pixels
    pixels = []
    # TODO: init mario
    mario = nil
    # create the level struct
    struct!(__MODULE__,
      pixels: pixels,
      mario: mario,
      ticker: 0,
      level: level,
      points: 0,
      gameover: false
    )
  end
end
