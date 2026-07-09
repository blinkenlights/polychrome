defmodule Octopus.Apps.PixelFun.ScenePresets do
  @moduledoc """
  Adapter over `Octopus.AppModePresets` for Pixel Fun.

  Keeps the legacy preset map shape (`formula` field, `builtin:` / `user:` ids)
  used by the full editor and existing tests.
  """

  alias Octopus.Apps.PixelFun.Program

  @app_mode_presets "Elixir.Octopus.AppModePresets"
  @pixel_fun "Elixir.Octopus.Apps.PixelFun"

  @type preset :: map()

  @doc "Returns user-facing presets (legacy shape)."
  @spec list_all() :: [preset()]
  def list_all do
    pixel_fun()
    |> presets().list_presets()
    |> Enum.map(&to_legacy/1)
  end

  @doc "Returns built-in presets only."
  @spec builtins() :: [preset()]
  def builtins do
    list_all() |> Enum.filter(& &1.builtin)
  end

  @doc "Returns user-saved presets only."
  @spec list_user() :: [preset()]
  def list_user do
    list_all() |> Enum.reject(& &1.builtin)
  end

  @spec get(String.t()) :: preset() | nil
  def get(mode_id) do
    case presets().get(pixel_fun(), mode_id) do
      nil -> nil
      preset -> to_legacy(preset)
    end
  end

  @spec create(map()) :: {:ok, preset()} | {:error, Ecto.Changeset.t() | atom()}
  def create(attrs) do
    name = Map.fetch!(attrs, :name)

    config = %{
      program: Map.get(attrs, :formula) || Map.get(attrs, :program),
      color_interval: Map.get(attrs, :color_interval, 5.0),
      translate_scale: Map.get(attrs, :translate_scale, 0.0),
      rotate_scale: Map.get(attrs, :rotate_scale, 0.0),
      zoom_scale: Map.get(attrs, :zoom_scale, 1.0)
    }

    opts = [accent_color: Map.get(attrs, :accent_color, presets().random_accent_color())]

    case presets().create(pixel_fun(), name, config, opts) do
      {:ok, preset} -> {:ok, to_legacy(preset)}
      {:error, :invalid_formula} -> {:error, invalid_formula_changeset(Map.get(attrs, :formula, ""))}
      error -> error
    end
  end

  @spec update(String.t(), map()) :: {:ok, preset()} | {:error, Ecto.Changeset.t() | atom()}
  def update(mode_id, attrs) do
    preset = presets().get(pixel_fun(), mode_id)
    base_config = normalize_config_keys((preset && preset.config) || %{})

    config =
      base_config
      |> Map.merge(flat_attrs_to_config(attrs))

    update_attrs =
      %{config: config}
      |> maybe_put_name(attrs)

    case presets().update(pixel_fun(), mode_id, update_attrs) do
      {:ok, preset} -> {:ok, to_legacy(preset)}
      error -> error
    end
  end

  @spec delete(String.t()) :: :ok | {:error, atom()}
  def delete(mode_id) do
    case presets().archive(pixel_fun(), mode_id) do
      :ok -> :ok
      {:error, :not_found} -> {:error, :not_found}
      _ -> {:error, :failed}
    end
  end

  @spec validate_formula(String.t()) :: :ok | :error
  def validate_formula(formula) when is_binary(formula) do
    case Program.parse(formula) do
      {:ok, _} -> :ok
      _ -> :error
    end
  end

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

  @spec attrs_from_config(map()) :: map()
  def attrs_from_config(config) do
    %{
      formula: Map.get(config, :program, ""),
      color_interval: Map.get(config, :color_interval, 5.0),
      translate_scale: Map.get(config, :translate_scale, 0.0),
      rotate_scale: Map.get(config, :rotate_scale, 0.0),
      zoom_scale: Map.get(config, :zoom_scale, 1.0)
    }
  end

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

  @spec id_for_config(map()) :: String.t()
  def id_for_config(config) do
    case presets().id_for_config(pixel_fun(), config) do
      "custom" ->
        "custom"

      id ->
        case presets().get(pixel_fun(), id) do
          nil -> id
          preset -> to_legacy(preset).id
        end
    end
  end

  @spec summary(preset()) :: String.t()
  def summary(%{} = preset) do
    apply(pixel_fun(), :summary_for_preset, [%{config: to_config(preset)}])
  end

  def random_accent_color, do: presets().random_accent_color()

  defp presets, do: String.to_existing_atom(@app_mode_presets)
  defp pixel_fun, do: String.to_existing_atom(@pixel_fun)

  defp to_legacy(%{} = preset) do
    config = preset.config

    %{
      id: legacy_id(preset),
      name: preset.name,
      formula: config[:program],
      color_interval: config[:color_interval],
      translate_scale: config[:translate_scale],
      rotate_scale: config[:rotate_scale],
      zoom_scale: config[:zoom_scale],
      accent_color: preset.accent_color,
      builtin: preset.builtin
    }
  end

  defp legacy_id(%{origin: :builtin, slug: slug}), do: "builtin:#{slug}"
  defp legacy_id(%{slug: "user_" <> _ = slug}), do: "user:" <> String.replace_prefix(slug, "user_", "")
  defp legacy_id(%{id: id}), do: id

  defp maybe_put_name(attrs, source) do
    case Map.get(source, :name) do
      nil -> attrs
      name -> Map.put(attrs, :name, name)
    end
  end

  defp flat_attrs_to_config(attrs) do
    %{}
    |> maybe_config_put(:program, Map.get(attrs, :formula) || Map.get(attrs, :program))
    |> maybe_config_put(:color_interval, Map.get(attrs, :color_interval))
    |> maybe_config_put(:translate_scale, Map.get(attrs, :translate_scale))
    |> maybe_config_put(:rotate_scale, Map.get(attrs, :rotate_scale))
    |> maybe_config_put(:zoom_scale, Map.get(attrs, :zoom_scale))
  end

  defp maybe_config_put(config, _key, nil), do: config
  defp maybe_config_put(config, key, value), do: Map.put(config, key, value)

  defp normalize_config_keys(config) when is_map(config) do
    Map.new(config, fn {k, v} -> {normalize_config_key(k), v} end)
  end

  defp normalize_config_key(k) when is_atom(k), do: k

  defp normalize_config_key(k) when is_binary(k) do
    case k do
      "true" -> :true
      "false" -> :false
      other -> String.to_existing_atom(other)
    end
  rescue
    ArgumentError -> String.to_atom(k)
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

  defp invalid_formula_changeset(formula) do
    %Octopus.Apps.PixelFun.ScenePreset{}
    |> Ecto.Changeset.change(%{formula: formula})
    |> Ecto.Changeset.add_error(:formula, "has invalid syntax")
  end
end
