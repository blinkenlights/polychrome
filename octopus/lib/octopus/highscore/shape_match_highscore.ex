defmodule Octopus.Highscore.ShapeMatchHighscore do
  use Ecto.Schema
  import Ecto.Changeset

  schema "shape_match_highscores" do
    field :score_seconds, :integer
    timestamps()
  end

  def changeset(highscore, attrs) do
    highscore
    |> cast(attrs, [:score_seconds])
    |> validate_required([:score_seconds])
  end
end
