defmodule Octopus.Apps.PixelFun.ScenePreset do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Octopus.Apps.PixelFun.Program

  schema "pixel_fun_presets" do
    field :name, :string
    field :formula, :string
    field :color_interval, :float
    field :translate_scale, :float
    field :rotate_scale, :float
    field :zoom_scale, :float
    field :accent_color, :string

    timestamps()
  end

  @scene_fields [
    :name,
    :formula,
    :color_interval,
    :translate_scale,
    :rotate_scale,
    :zoom_scale,
    :accent_color
  ]

  def changeset(preset, attrs) do
    preset
    |> cast(attrs, @scene_fields)
    |> validate_required(@scene_fields)
    |> validate_length(:name, min: 1, max: 100)
    |> validate_formula()
    |> validate_accent_color()
    |> validate_number(:color_interval, greater_than: 0)
    |> validate_number(:translate_scale, greater_than_or_equal_to: 0)
    |> validate_number(:rotate_scale, greater_than_or_equal_to: -4, less_than_or_equal_to: 4)
    |> validate_number(:zoom_scale, greater_than_or_equal_to: 0)
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

  defp validate_accent_color(changeset) do
    case get_field(changeset, :accent_color) do
      nil ->
        changeset

      color when is_binary(color) ->
        if Regex.match?(~r/^#[0-9A-Fa-f]{6}$/, color) do
          changeset
        else
          add_error(changeset, :accent_color, "must be #RRGGBB")
        end

      _ ->
        add_error(changeset, :accent_color, "must be #RRGGBB")
    end
  end
end
