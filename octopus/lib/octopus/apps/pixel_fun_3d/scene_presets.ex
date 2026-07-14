defmodule Octopus.Apps.PixelFun3D.ScenePresets do
  @moduledoc """
  Read-only adapter over `Octopus.AppModePresets` for Pixel Fun 3D.

  Keeps the legacy preset map shape (`formula` field, `builtin:` ids) used by the
  full editor and existing tests.
  """

  alias Octopus.Apps.PixelFun3D
  alias Octopus.Apps.PixelFun.Program

  @app_mode_presets "Elixir.Octopus.AppModePresets"
  @pixel_fun "Elixir.Octopus.Apps.PixelFun3D"

  @sphere_defaults %{
    brightness_percent: 100,
    orbit_rate: 0.0,
    roll_rate: 0.0,
    roll_pivot: 0,
    tilt_scale: 0.0,
    tilt_speed: 0.5,
    tilt_mode: :wobble,
    elev_base: 0.0,
    zoom_base: 1.0,
    zoom_pivot: 0,
    pattern_speed: 1.0,
    trans_auto: false,
    trans_auto_range_x: 6.0,
    trans_auto_range_y: 2.0,
    trans_auto_interval: 30.0,
    rot_auto: false,
    rot_auto_range: 30.0,
    rot_auto_interval: 30.0,
    zoom_auto: false,
    zoom_auto_range: 1.5,
    zoom_auto_interval: 30.0,
    sway_auto: false,
    sway_auto_range: 2.0,
    sway_auto_interval: 30.0,
    sat_auto: false,
    sat_auto_min: 20.0,
    sat_auto_max: 100.0,
    sat_auto_interval: 30.0
  }

  @sphere_keys Map.keys(@sphere_defaults)

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
      palette_phase: Map.get(preset, :palette_phase, 0.0),
      color_interval: preset.color_interval,
      palette_auto: Map.get(preset, :palette_auto, true),
      time_direction: normalize_time_direction(Map.get(preset, :time_direction, :forward))
    }
    |> Map.merge(Map.take(preset, @sphere_keys))
    |> PixelFun3D.migrate_legacy_config()
    |> Map.update!(:time_direction, &normalize_time_direction/1)
    |> Map.update!(:tilt_mode, &Octopus.Sway.normalize_mode/1)
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
    config = PixelFun3D.migrate_legacy_config(preset.config)

    %{
      id: legacy_id(preset),
      name: preset.name,
      formula: config[:program],
      palette_phase: Map.get(config, :palette_phase, 0.0),
      color_interval: config[:color_interval],
      time_direction: Map.get(config, :time_direction, :forward),
      accent_color: preset.accent_color,
      builtin: preset.builtin,
      palette_auto: Map.get(config, :palette_auto, true)
    }
    |> Map.merge(Map.take(config, @sphere_keys))
  end

  defp legacy_id(%{origin: :builtin, slug: slug}), do: "builtin:#{slug}"
  defp legacy_id(%{slug: "user_" <> _ = slug}), do: "user:" <> String.replace_prefix(slug, "user_", "")
  defp legacy_id(%{id: id}), do: id

  defp normalize_time_direction(:forward), do: :forward
  defp normalize_time_direction(:backward), do: :backward
  defp normalize_time_direction("forward"), do: :forward
  defp normalize_time_direction("backward"), do: :backward
  defp normalize_time_direction(_), do: :forward
end
