defmodule Octopus.Repo.Migrations.CreateShapeMatchHighscores do
  use Ecto.Migration

  def change do
    create table(:shape_match_highscores) do
      add :score_seconds, :integer, null: false
      timestamps()
    end
  end
end
