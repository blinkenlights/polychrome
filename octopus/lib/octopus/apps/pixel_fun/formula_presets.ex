defmodule Octopus.Apps.PixelFun.FormulaPresets do
  @moduledoc """
  Built-in and user-saved formula presets for Pixel Fun.

  Built-ins are defined in code; user presets are stored in SQLite.
  Each preset is exposed as a map with `:id`, `:name`, `:formula`, and `:builtin`.
  """

  import Ecto.Query, only: [order_by: 2]

  alias Octopus.Apps.PixelFun.FormulaPreset
  alias Octopus.Apps.PixelFun.Program
  alias Octopus.Repo

  @type preset :: %{
          id: String.t(),
          name: String.t(),
          formula: String.t(),
          builtin: boolean()
        }

  @builtins [
    %{
      id: "builtin:classic_ripple",
      name: "Classic ripple",
      formula: "sin(10*t-hypot(x,y))",
      builtin: true
    },
    %{
      id: "builtin:cross_waves",
      name: "Cross waves",
      formula: "sin(x*0.7+t*2)*cos(y*0.7-t*1.3)",
      builtin: true
    },
    %{
      id: "builtin:xy_interference",
      name: "XY interference",
      formula: "sin(x*y*0.08 - t*3)",
      builtin: true
    },
    %{
      id: "builtin:nested_sincos",
      name: "Nested sin/cos",
      formula: "sin(x*0.4+sin(y*0.3+t)*3+t)*cos(y*0.4+cos(x*0.3-t)*3-t)",
      builtin: true
    },
    %{
      id: "builtin:layered_waves",
      name: "Layered waves",
      formula: "sin(x*0.5+t)*cos(y*0.5-t)+sin((x+y)*0.35+t*1.5)*0.5",
      builtin: true
    },
    %{
      id: "builtin:ripple_rings",
      name: "Ripple rings",
      formula: "sin(hypot(x,y)*5-t*3)*sin(hypot(x+3,y+3)*5+t*2)",
      builtin: true
    },
    %{
      id: "builtin:organic_swirl",
      name: "Organic swirl",
      formula: "sin(x*y*0.06+sin(t)*x*0.2-t*2)*cos(hypot(x,y)*2+t)",
      builtin: true
    }
  ]

  @doc "Returns built-in presets (not stored in the database)."
  @spec builtins() :: [preset()]
  def builtins, do: @builtins

  @doc "Returns built-in presets followed by user-saved presets."
  @spec list_all() :: [preset()]
  def list_all do
    builtins() ++ list_user()
  end

  @doc "Returns user-saved presets from the database."
  @spec list_user() :: [preset()]
  def list_user do
    FormulaPreset
    |> order_by(asc: :name)
    |> Repo.all()
    |> Enum.map(&to_preset/1)
  end

  @doc "Looks up a preset by id (`builtin:…` or `user:…`)."
  @spec get(String.t()) :: preset() | nil
  def get("builtin:" <> slug) do
    Enum.find(builtins(), &(&1.id == "builtin:#{slug}"))
  end

  def get("user:" <> id) do
    case Integer.parse(id) do
      {db_id, ""} ->
        case Repo.get(FormulaPreset, db_id) do
          nil -> nil
          record -> to_preset(record)
        end

      _ ->
        nil
    end
  end

  def get(_), do: nil

  @doc "Creates a user preset. Returns `{:ok, preset}` or `{:error, changeset}`."
  @spec create(map()) :: {:ok, preset()} | {:error, Ecto.Changeset.t()}
  def create(attrs) do
    %FormulaPreset{}
    |> FormulaPreset.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, record} -> {:ok, to_preset(record)}
      error -> error
    end
  end

  @doc "Deletes a user preset by id. Built-ins cannot be deleted."
  @spec delete(String.t()) :: :ok | {:error, :not_found | :builtin}
  def delete("user:" <> id) do
    case Integer.parse(id) do
      {db_id, ""} ->
        case Repo.get(FormulaPreset, db_id) do
          nil ->
            {:error, :not_found}

          record ->
            case Repo.delete(record) do
              {:ok, _} -> :ok
              {:error, _} -> {:error, :not_found}
            end
        end

      _ ->
        {:error, :not_found}
    end
  end

  def delete("builtin:" <> _), do: {:error, :builtin}
  def delete(_), do: {:error, :not_found}

  @doc "Returns `:ok` if the formula parses, otherwise `:error`."
  @spec validate_formula(String.t()) :: :ok | :error
  def validate_formula(formula) when is_binary(formula) do
    case Program.parse(formula) do
      {:ok, _} -> :ok
      _ -> :error
    end
  end

  @doc "Returns true if a user-saved preset already uses this exact formula."
  @spec user_formula_exists?(String.t()) :: boolean()
  def user_formula_exists?(formula) when is_binary(formula) do
    Enum.any?(list_user(), &(&1.formula == formula))
  end

  @doc "Returns a preset id for an exact formula match, or `\"custom\"`."
  @spec id_for_formula(String.t()) :: String.t()
  def id_for_formula(formula) do
    case Enum.find(list_all(), &(&1.formula == formula)) do
      nil -> "custom"
      preset -> preset.id
    end
  end

  defp to_preset(%FormulaPreset{id: id, name: name, formula: formula}) do
    %{id: "user:#{id}", name: name, formula: formula, builtin: false}
  end
end
