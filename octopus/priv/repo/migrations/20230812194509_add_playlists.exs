defmodule Octopus.Repo.Migrations.AddPlaylists do
  use Ecto.Migration

  def change do
    create table(:playlists) do
      add :name, :string, null: false
      add :animations, {:array, :map}, default: []
      timestamps()
    end
  end
end
