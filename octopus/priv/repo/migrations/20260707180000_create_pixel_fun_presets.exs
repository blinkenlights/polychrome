defmodule Octopus.Repo.Migrations.CreatePixelFunPresets do
  use Ecto.Migration

  def up do
    create table(:pixel_fun_presets) do
      add :name, :string, null: false
      add :formula, :text, null: false
      add :color_interval, :float, null: false, default: 5.0
      add :translate_scale, :float, null: false, default: 0.0
      add :rotate_scale, :float, null: false, default: 0.0
      add :zoom_scale, :float, null: false, default: 1.0
      add :accent_color, :string, null: false

      timestamps()
    end

    create unique_index(:pixel_fun_presets, [:name])

    if legacy_formula_presets_table?() do
      execute("""
      INSERT INTO pixel_fun_presets (
        name, formula, color_interval, translate_scale, rotate_scale, zoom_scale,
        accent_color, inserted_at, updated_at
      )
      SELECT
        name,
        formula,
        5.0,
        0.0,
        0.0,
        1.0,
        '#4A90D9',
        datetime('now'),
        datetime('now')
      FROM pixel_fun_formula_presets
      """)

      drop table(:pixel_fun_formula_presets)
    end
  end

  defp legacy_formula_presets_table? do
    case repo().query(
           "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1",
           ["pixel_fun_formula_presets"]
         ) do
      {:ok, %{num_rows: 1}} -> true
      _ -> false
    end
  end

  def down do
    create table(:pixel_fun_formula_presets) do
      add :name, :string, null: false
      add :formula, :text, null: false

      timestamps()
    end

    create unique_index(:pixel_fun_formula_presets, [:name])

    execute("""
    INSERT INTO pixel_fun_formula_presets (name, formula, inserted_at, updated_at)
    SELECT name, formula, inserted_at, updated_at
    FROM pixel_fun_presets
    """)

    drop table(:pixel_fun_presets)
  end
end
