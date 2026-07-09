defmodule Octopus.Repo.Migrations.CreateAppModePresets do
  use Ecto.Migration

  def up do
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

    migrate_pixel_fun_presets()
  end

  def down do
    drop table(:app_mode_presets)
  end

  defp migrate_pixel_fun_presets do
    if table?(:pixel_fun_presets) do
      execute("""
      INSERT INTO app_mode_presets (app, slug, name, config, accent_color, origin, inserted_at, updated_at)
      SELECT
        'Octopus.Apps.PixelFun',
        'user_' || id,
        name,
        json_object(
          'program', formula,
          'color_interval', color_interval,
          'translate_scale', translate_scale,
          'rotate_scale', rotate_scale,
          'zoom_scale', zoom_scale
        ),
        accent_color,
        'user',
        inserted_at,
        updated_at
      FROM pixel_fun_presets
      """)
    end
  end

  defp table?(name) do
    case repo().query(
           "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1",
           [name]
         ) do
      {:ok, %{num_rows: 1}} -> true
      _ -> false
    end
  end
end
