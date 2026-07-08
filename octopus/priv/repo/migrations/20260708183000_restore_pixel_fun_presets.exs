defmodule Octopus.Repo.Migrations.RestorePixelFunPresets do
  use Ecto.Migration

  def up do
    unless presets_table?() do
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
    end

    if formula_table?() do
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
        COALESCE(inserted_at, datetime('now')),
        COALESCE(updated_at, datetime('now'))
      FROM pixel_fun_formula_presets
      WHERE name NOT IN (SELECT name FROM pixel_fun_presets)
      """)

      drop(table(:pixel_fun_formula_presets))
    end
  end

  def down do
    # Irreversible — prior migration state was inconsistent.
    :ok
  end

  defp presets_table? do
    table?("pixel_fun_presets")
  end

  defp formula_table? do
    table?("pixel_fun_formula_presets")
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
