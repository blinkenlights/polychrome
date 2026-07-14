defmodule Octopus.Repo.Migrations.DropAppModePresets do
  use Ecto.Migration

  def up do
    drop_if_exists table(:app_mode_presets)
    drop_if_exists table(:pixel_fun_presets)
    drop_if_exists table(:pixel_fun_formula_presets)
  end

  def down do
    create table(:app_mode_presets) do
      add :app, :string, null: false
      add :slug, :string, null: false
      add :name, :string, null: false
      add :config, :map, null: false, default: %{}
      add :accent_color, :string, null: false
      add :origin, :string, null: false, default: "user"
      add :archived_at, :utc_datetime

      timestamps()
    end

    create index(:app_mode_presets, [:app])
    create unique_index(:app_mode_presets, [:app, :slug], where: "archived_at IS NULL")
  end
end
