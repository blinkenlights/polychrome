defmodule Octopus.Repo.Migrations.FixPixelFunFormulaPresetsTable do
  use Ecto.Migration

  def up do
    create_if_not_exists table(:pixel_fun_formula_presets) do
      add :name, :string, null: false
      add :formula, :text, null: false

      timestamps()
    end

    create_if_not_exists unique_index(:pixel_fun_formula_presets, [:name])

    if legacy_presets_table?() do
      execute(
        """
        INSERT INTO pixel_fun_formula_presets (name, formula, inserted_at, updated_at)
        SELECT name, formula, inserted_at, updated_at
        FROM pixel_fun_presets
        WHERE name NOT IN (SELECT name FROM pixel_fun_formula_presets)
        """,
        ""
      )

      drop(table(:pixel_fun_presets))
    end
  end

  def down do
    drop_if_exists(table(:pixel_fun_formula_presets))
  end

  defp legacy_presets_table? do
    case Ecto.Adapters.SQL.query(
           repo(),
           "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'pixel_fun_presets' LIMIT 1",
           []
         ) do
      {:ok, %{num_rows: 1}} -> true
      _ -> false
    end
  end
end
