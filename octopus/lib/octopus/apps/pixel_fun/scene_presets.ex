defmodule Octopus.Apps.PixelFun.ScenePresets do
  @moduledoc """
  Read-only adapter over `Octopus.AppModePresets` for Pixel Fun.

  Keeps the legacy preset map shape (`formula` field, `builtin:` ids) used by the
  full editor and existing tests.
  """

  alias Octopus.Apps.PixelFun.Program

  @app_mode_presets "Elixir.Octopus.AppModePresets"
  @pixel_fun "Elixir.Octopus.Apps.PixelFun"

  @sway_defaults %{sway_scale: 0.0, sway_speed: 0.5, sway_mode: :wobble}

  @type preset :: map()

  @spec list_all() :: [preset()]
  def list_all do
    pixel_fun()
    |> presets().list_presets()
    |> Enum.map(&to_legacy/1)
  end

  @spec builtins() :: [preset()]
  def builtins do
    list_all()
  end

  @spec get(String.t()) :: preset() | nil
  def get(mode_id) do
    case presets().get(pixel_fun(), mode_id) do
      nil -> nil
      preset -> to_legacy(preset)
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
      zoom_scale: preset.zoom_scale,
      sway_scale: Map.get(preset, :sway_scale, @sway_defaults.sway_scale),
      sway_speed: Map.get(preset, :sway_speed, @sway_defaults.sway_speed),
      sway_mode: normalize_sway_mode(Map.get(preset, :sway_mode, @sway_defaults.sway_mode)),
      time_direction: normalize_time_direction(Map.get(preset, :time_direction, :forward))
    }
  end

  @spec config_matches?(map(), map()) :: boolean()
  def config_matches?(config, %{id: id}) do
    id_for_config(config) == id
  end

  def config_matches?(left, right) when is_map(left) and is_map(right) do
    id_for_config(left) == id_for_config(right)
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
      sway_scale: Map.get(config, :sway_scale, @sway_defaults.sway_scale),
      sway_speed: Map.get(config, :sway_speed, @sway_defaults.sway_speed),
      sway_mode: normalize_sway_mode(Map.get(config, :sway_mode, @sway_defaults.sway_mode)),
      time_direction: normalize_time_direction(Map.get(config, :time_direction, :forward)),
      accent_color: preset.accent_color,
      builtin: preset.builtin
    }
  end

  defp legacy_id(%{origin: :builtin, slug: slug}), do: "builtin:#{slug}"
  defp legacy_id(%{slug: "user_" <> _ = slug}), do: "user:" <> String.replace_prefix(slug, "user_", "")
  defp legacy_id(%{id: id}), do: id

  defp normalize_sway_mode(:wobble), do: :wobble
  defp normalize_sway_mode(:pendulum), do: :pendulum
  defp normalize_sway_mode("wobble"), do: :wobble
  defp normalize_sway_mode("pendulum"), do: :pendulum
  defp normalize_sway_mode(_), do: :wobble

  defp normalize_time_direction(:forward), do: :forward
  defp normalize_time_direction(:backward), do: :backward
  defp normalize_time_direction("forward"), do: :forward
  defp normalize_time_direction("backward"), do: :backward
  defp normalize_time_direction(_), do: :forward
end
