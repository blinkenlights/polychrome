defmodule Octopus.Repo.Migrations.CreateSoundCompositions do
  use Ecto.Migration

  def change do
    create table(:sound_compositions) do
      add :name, :string, null: false
      add :pattern, :map, null: false, default: %{}
      add :bpm, :float, null: false, default: 120.0
      # The formula that was on the wall when this was saved — informational,
      # so a composition can be recognised by the picture it belongs to.
      add :scene, :string

      timestamps()
    end

    create unique_index(:sound_compositions, [:name])
  end
end
