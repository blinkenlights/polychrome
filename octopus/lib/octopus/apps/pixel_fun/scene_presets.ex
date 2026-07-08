defmodule Octopus.Apps.PixelFun.ScenePresets do
  @moduledoc """
  Built-in and user-saved scene presets for Pixel Fun.

  Each preset includes formula, slider values, and a tile accent color.
  """

  import Ecto.Query, only: [order_by: 2]

  alias Octopus.Apps.PixelFun.Program
  alias Octopus.Apps.PixelFun.ScenePreset
  alias Octopus.Repo

  @type preset :: %{
          id: String.t(),
          name: String.t(),
          formula: String.t(),
          color_interval: float(),
          translate_scale: float(),
          rotate_scale: float(),
          zoom_scale: float(),
          accent_color: String.t(),
          builtin: boolean()
        }

  @default_scene %{
    color_interval: 5.0,
    translate_scale: 0.0,
    rotate_scale: 0.0,
    zoom_scale: 1.0
  }

  @builtins [
    %{
      id: "builtin:classic_ripple",
      name: "Classic ripple",
      formula: "sin(10*t-hypot(x,y))",
      accent_color: "#E74C3C",
      builtin: true
    },
    %{
      id: "builtin:cross_waves",
      name: "Cross waves",
      formula: "sin(x*0.7+t*2)*cos(y*0.7-t*1.3)",
      accent_color: "#3498DB",
      builtin: true
    },
    %{
      id: "builtin:xy_interference",
      name: "XY interference",
      formula: "sin(x*y*0.08 - t*3)",
      accent_color: "#9B59B6",
      builtin: true
    },
    %{
      id: "builtin:nested_sincos",
      name: "Nested sin/cos",
      formula: "sin(x*0.4+sin(y*0.3+t)*3+t)*cos(y*0.4+cos(x*0.3-t)*3-t)",
      accent_color: "#1ABC9C",
      builtin: true
    },
    %{
      id: "builtin:layered_waves",
      name: "Layered waves",
      formula: "sin(x*0.5+t)*cos(y*0.5-t)+sin((x+y)*0.35+t*1.5)*0.5",
      accent_color: "#F39C12",
      builtin: true
    },
    %{
      id: "builtin:ripple_rings",
      name: "Ripple rings",
      formula: "sin(hypot(x,y)*5-t*3)*sin(hypot(x+3,y+3)*5+t*2)",
      accent_color: "#E91E63",
      builtin: true
    },
    %{
      id: "builtin:organic_swirl",
      name: "Organic swirl",
      formula: "sin(x*y*0.06+sin(t)*x*0.2-t*2)*cos(hypot(x,y)*2+t)",
      accent_color: "#2ECC71",
      builtin: true
    }
  ]
  |> Enum.map(&Map.merge(@default_scene, &1))

  @doc "Returns built-in scene presets (not stored in the database)."
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
    ScenePreset
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
        case Repo.get(ScenePreset, db_id) do
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
    attrs =
      @default_scene
      |> Map.merge(Map.new(attrs))
      |> Map.put_new(:accent_color, random_accent_color())
      |> Map.take([
        :name,
        :formula,
        :color_interval,
        :translate_scale,
        :rotate_scale,
        :zoom_scale,
        :accent_color
      ])

    %ScenePreset{}
    |> ScenePreset.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, record} -> {:ok, to_preset(record)}
      error -> error
    end
  end

  @doc "Updates a user preset. Built-ins cannot be updated."
  @spec update(String.t(), map()) :: {:ok, preset()} | {:error, Ecto.Changeset.t() | atom()}
  def update("user:" <> id, attrs) do
    case Integer.parse(id) do
      {db_id, ""} ->
        case Repo.get(ScenePreset, db_id) do
          nil ->
            {:error, :not_found}

          record ->
            record
            |> ScenePreset.changeset(attrs)
            |> Repo.update()
            |> case do
              {:ok, updated} -> {:ok, to_preset(updated)}
              error -> error
            end
        end

      _ ->
        {:error, :not_found}
    end
  end

  def update("builtin:" <> _, _attrs), do: {:error, :builtin}
  def update(_, _attrs), do: {:error, :not_found}

  @doc "Deletes a user preset by id. Built-ins cannot be deleted."
  @spec delete(String.t()) :: :ok | {:error, :not_found | :builtin}
  def delete("user:" <> id) do
    case Integer.parse(id) do
      {db_id, ""} ->
        case Repo.get(ScenePreset, db_id) do
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

  @doc "Converts a preset to the app config fields it controls."
  @spec to_config(preset()) :: map()
  def to_config(%{} = preset) do
    %{
      program: preset.formula,
      color_interval: preset.color_interval,
      translate_scale: preset.translate_scale,
      rotate_scale: preset.rotate_scale,
      zoom_scale: preset.zoom_scale
    }
  end

  @doc "Builds preset attrs from the live editor config."
  @spec attrs_from_config(map()) :: map()
  def attrs_from_config(config) do
    %{
      formula: Map.get(config, :program, ""),
      color_interval: Map.get(config, :color_interval, @default_scene.color_interval),
      translate_scale: Map.get(config, :translate_scale, @default_scene.translate_scale),
      rotate_scale: Map.get(config, :rotate_scale, @default_scene.rotate_scale),
      zoom_scale: Map.get(config, :zoom_scale, @default_scene.zoom_scale)
    }
  end

  @doc "Returns true when config matches a preset's scene fields."
  @spec config_matches?(map(), map()) :: boolean()
  def config_matches?(config, preset_or_snapshot) do
    snapshot = normalize_snapshot(preset_or_snapshot)

    Enum.all?(
      [:program, :color_interval, :translate_scale, :rotate_scale, :zoom_scale],
      fn key ->
        float_eq?(Map.get(config, key), Map.get(snapshot, key))
      end
    )
  end

  @doc "Returns a preset id for an exact scene match, or `\"custom\"`."
  @spec id_for_config(map()) :: String.t()
  def id_for_config(config) do
    case Enum.find(list_all(), &config_matches?(config, &1)) do
      nil -> "custom"
      preset -> preset.id
    end
  end

  @doc "One-line tile summary for a preset."
  @spec summary(preset()) :: String.t()
  def summary(%{} = preset) do
    sliders =
      "drift #{format_num(preset.translate_scale)} · rot #{format_num(preset.rotate_scale)} · zoom #{format_num(preset.zoom_scale)} · palette #{format_num(preset.color_interval)}s"

    formula =
      preset.formula
      |> String.trim()
      |> then(fn f -> if String.length(f) > 28, do: String.slice(f, 0, 25) <> "...", else: f end)

    "#{sliders} · #{formula}"
  end

  @doc "Random `#RRGGBB` accent color for new presets."
  @spec random_accent_color() :: String.t()
  def random_accent_color do
    <<r, g, b>> = :crypto.strong_rand_bytes(3)
    "#" <> Base.encode16(<<r, g, b>>, case: :upper)
  end

  defp to_preset(%ScenePreset{} = record) do
    %{
      id: "user:#{record.id}",
      name: record.name,
      formula: record.formula,
      color_interval: record.color_interval,
      translate_scale: record.translate_scale,
      rotate_scale: record.rotate_scale,
      zoom_scale: record.zoom_scale,
      accent_color: record.accent_color,
      builtin: false
    }
  end

  defp normalize_snapshot(%{formula: formula} = preset) do
    %{
      program: formula,
      color_interval: preset.color_interval,
      translate_scale: preset.translate_scale,
      rotate_scale: preset.rotate_scale,
      zoom_scale: preset.zoom_scale
    }
  end

  defp normalize_snapshot(%{program: _} = snapshot), do: snapshot

  defp float_eq?(a, b) when is_number(a) and is_number(b), do: abs(a - b) < 0.001
  defp float_eq?(a, b), do: a == b

  defp format_num(n) when is_float(n), do: :erlang.float_to_binary(n, decimals: 1)
  defp format_num(n) when is_integer(n), do: Integer.to_string(n)
  defp format_num(n), do: to_string(n)
end
