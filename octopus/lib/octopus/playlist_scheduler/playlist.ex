defmodule Octopus.PlaylistScheduler.Playlist do
  use Ecto.Schema
  alias Ecto.Changeset
  alias Octopus.AppSupervisor

  defmodule Animation do
    use Ecto.Schema

    @derive {Jason.Encoder, except: [:id]}
    embedded_schema do
      field :app, :string
      field :config, :map, default: %{}
      field :timeout, :integer, default: 60_000
    end
  end

  schema "playlists" do
    field :name, :string

    embeds_many :animations, Animation, on_replace: :delete

    timestamps()
  end

  def changeset(playlist = %__MODULE__{}, attrs) do
    playlist
    |> Changeset.cast(attrs, [:name])
    |> Changeset.cast_embed(:animations, with: &animation_changeset/2)
    |> Changeset.validate_required([:name])
  end

  def animation_changeset(%__MODULE__.Animation{} = animation, attrs) do
    animation
    |> Changeset.cast(attrs, [:app, :config, :timeout])
    |> Changeset.validate_change(:app, &validate_app/2)
    |> Changeset.validate_change(:config, &validate_config/2)
    |> Changeset.validate_number(:timeout, greater_than: 0)
  end

  defp validate_app(:app, app) do
    valid_apps =
      AppSupervisor.available_apps()
      |> Enum.map(fn module -> Module.split(module) |> List.last() end)

    if app in valid_apps do
      []
    else
      [app: "does not exist"]
    end
  end

  defp validate_config(:config, config) do
    # todo
    []
  end
end
