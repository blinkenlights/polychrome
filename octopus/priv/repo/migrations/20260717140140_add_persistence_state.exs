defmodule Octopus.Repo.Migrations.AddPersistenceState do
  use Ecto.Migration

  def change do
    create table(:installation_transport_state) do
      add :queue, {:array, :map}, default: []
      add :cycle_index, :integer, default: 0
      add :cycle_interval_seconds, :float, default: 300.0
      add :transition_duration_seconds, :float, default: 1.0
      add :playing, :boolean, default: true

      timestamps()
    end

    create table(:playlist_scheduler_state) do
      add :playlist_id, :string, null: false
      add :index, :integer, default: 0, null: false
      add :running, :boolean, default: false, null: false

      timestamps()
    end
  end
end
