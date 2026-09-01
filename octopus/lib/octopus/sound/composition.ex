defmodule Octopus.Sound.Composition do
  @moduledoc """
  A saved state of the studio: the pattern, the tempo, and which picture it
  belonged to.

  Compositions live in the database rather than in the JSON preset files under
  `priv/app_mode_presets`, because those are read at compile time and cannot be
  written at runtime — and a composition is something you make while listening,
  not something you deploy. Putting them in the rotation is a separate step
  (see `docs/pixelfun-av/03-ui.md`, "Freigabe").
  """

  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Octopus.Repo
  alias Octopus.Sound.{Pattern, Patch}

  schema "sound_compositions" do
    field :name, :string
    field :pattern, :map, default: %{}
    field :bpm, :float, default: 120.0
    field :scene, :string

    timestamps()
  end

  @doc false
  def changeset(composition, attrs) do
    composition
    |> cast(attrs, [:name, :pattern, :bpm, :scene])
    |> validate_required([:name, :pattern])
    |> validate_length(:name, min: 1, max: 120)
    |> validate_number(:bpm, greater_than: 0, less_than_or_equal_to: 400)
    |> unique_constraint(:name)
  end

  @doc "All compositions, newest first."
  def list do
    Repo.all(from c in __MODULE__, order_by: [desc: c.updated_at])
  end

  def get(id), do: Repo.get(__MODULE__, id)

  @doc """
  Saves under `name`, replacing a composition of the same name.

  Overwriting by name is deliberate: while composing you save the same thing
  again and again, and a list full of "Ring-Chase 3 (7)" helps nobody. Use
  `take/3` when you want to keep a moment.
  """
  @spec save(String.t(), Pattern.t(), keyword()) ::
          {:ok, %__MODULE__{}} | {:error, Ecto.Changeset.t()}
  def save(name, %Pattern{} = pattern, opts \\ []) do
    attrs = %{
      name: name,
      pattern: Pattern.to_map(pattern),
      bpm: Keyword.get(opts, :bpm, 120.0) / 1,
      scene: Keyword.get(opts, :scene)
    }

    case Repo.get_by(__MODULE__, name: name) do
      nil -> %__MODULE__{}
      existing -> existing
    end
    |> changeset(attrs)
    |> Repo.insert_or_update()
  end

  @doc "Saves a copy under a timestamped name, so the working version stays untouched."
  @spec take(Pattern.t(), keyword()) :: {:ok, %__MODULE__{}} | {:error, Ecto.Changeset.t()}
  def take(%Pattern{} = pattern, opts \\ []) do
    stamp = Calendar.strftime(DateTime.utc_now(), "%Y-%m-%d %H:%M:%S")
    save("Take #{stamp}", pattern, opts)
  end

  @doc "Loads a composition into the live patch and returns it."
  @spec load(integer()) :: {:ok, %__MODULE__{}} | :error
  def load(id) do
    case get(id) do
      nil ->
        :error

      composition ->
        composition.pattern |> Pattern.from_map() |> Patch.put()
        {:ok, composition}
    end
  end

  def delete(id) do
    case get(id) do
      nil -> :error
      composition -> Repo.delete(composition)
    end
  end
end
