defmodule Octopus.Repo.Migrations.CreatePixelFunFormulaPresets do
  use Ecto.Migration

  def change do
    create table(:pixel_fun_formula_presets) do
      add :name, :string, null: false
      add :formula, :text, null: false

      timestamps()
    end

    create unique_index(:pixel_fun_formula_presets, [:name])
  end
end
