defmodule Octopus.Apps.Hogg.Game do
  defstruct [:round]
  alias Octopus.Apps.Hogg

  alias Hogg.Game
  alias Hogg.Round

  def new() do
    %Game{
      round: Round.new()
    }
  end

  def tick(%Game{} = game, joylist) do
    %Game{
      game
      | round: game.round |> Round.tick(joylist)
    }
  end

  def render_frame(%Game{} = game) do
    game.round
    |> Round.render_frame()
  end
end
