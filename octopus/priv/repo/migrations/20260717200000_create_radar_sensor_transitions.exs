defmodule Octopus.Repo.Migrations.CreateRadarSensorTransitions do
  use Ecto.Migration

  def change do
    create table(:radar_sensor_transitions) do
      add :device_id, :integer, null: false
      add :status, :string, null: false
      # Wall-clock milliseconds since Unix epoch; avoids timezone/precision
      # ambiguities of datetime columns in SQLite and makes range queries fast.
      add :occurred_at_ms, :integer, null: false

      timestamps(updated_at: false)
    end

    create index(:radar_sensor_transitions, [:device_id, :occurred_at_ms])
  end
end
