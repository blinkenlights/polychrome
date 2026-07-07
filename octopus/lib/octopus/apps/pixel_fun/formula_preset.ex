defmodule Octopus.Apps.PixelFun.FormulaPreset do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Octopus.Apps.PixelFun.Program

  schema "pixel_fun_formula_presets" do
    field :name, :string
    field :formula, :string

    timestamps()
  end

  def changeset(preset, attrs) do
    preset
    |> cast(attrs, [:name, :formula])
    |> validate_required([:name, :formula])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_formula()
    |> unique_constraint(:name)
  end

  defp validate_formula(changeset) do
    case get_field(changeset, :formula) do
      nil ->
        changeset

      formula ->
        case Program.parse(formula) do
          {:ok, _} -> changeset
          _ -> add_error(changeset, :formula, "has invalid syntax")
        end
    end
  end
end
