defmodule Octopus.AppModePreset do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @origins ~w(builtin user)

  schema "app_mode_presets" do
    field :app, :string
    field :slug, :string
    field :name, :string
    field :config, :map, default: %{}
    field :accent_color, :string
    field :origin, :string, default: "user"
    field :archived_at, :utc_datetime

    timestamps()
  end

  def changeset(preset, attrs) do
    preset
    |> cast(attrs, [:app, :slug, :name, :config, :accent_color, :origin, :archived_at])
    |> validate_required([:app, :slug, :name, :config, :accent_color, :origin])
    |> validate_inclusion(:origin, @origins)
    |> validate_length(:name, min: 1, max: 100)
    |> validate_accent_color()
    |> unique_constraint([:app, :slug], name: :app_mode_presets_app_slug_index)
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
