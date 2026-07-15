defmodule Octopus.AppModePresets do
  @moduledoc """
  Compile-time JSON mode presets for foyer apps (Pixel Fun, Pixel Fun 3D, Collective,
  Matrix, Perlin Noise, Ocean, Sand, Sparkle Mist, Wood, Fire, Gravity Mask).

  Presets live under `priv/app_mode_presets/{app_key}/{app_key}-settings.json` and are
  embedded at compile time via `Octopus.AppModePresets.Loader`.

  Mode ids use `app_key:slug`, e.g. `pixelfun:classic_ripple`, `pixelfun3d:classic_ripple`,
  `collective:storm`. Legacy Pixel Fun ids (`builtin:…`, `user:…`) and bare Collective
  slugs are accepted via `normalize_mode_id/2`.
  """

  alias Octopus.AppModePresets.Loader

  @installation_transport Module.concat(["Octopus", "InstallationTransport"])

  # String module names avoid compile-time deps on app modules that call back into this module.
  @app_keys %{
    "Elixir.Octopus.Apps.PixelFun" => "pixelfun",
    "Elixir.Octopus.Apps.PixelFun3D" => "pixelfun3d",
    "Elixir.Octopus.Apps.Collective" => "collective",
    "Elixir.Octopus.Apps.Matrix" => "matrix",
    "Elixir.Octopus.Apps.PerlinNoise" => "perlinnoise",
    "Elixir.Octopus.Apps.Ocean" => "ocean",
    "Elixir.Octopus.Apps.Sand" => "sand",
    "Elixir.Octopus.Apps.SparkleMist" => "sparklemist",
    "Elixir.Octopus.Apps.Wood" => "wood",
    "Elixir.Octopus.Apps.Fire" => "fire",
    "Elixir.Octopus.Apps.GravityMask" => "gravitymask",
    "Elixir.Octopus.Apps.ShapeShifter" => "shapeshifter"
  }

  @formula_app_keys ~w(pixelfun pixelfun3d)

  @doc false
  def persistable_apps do
    @app_keys
    |> Map.keys()
    |> Enum.map(&String.to_existing_atom/1)
  end

  @doc false
  def persistable?(app) when is_atom(app), do: Map.has_key?(@app_keys, Atom.to_string(app))
  def persistable?(_), do: false

  @doc false
  def app_key(app) when is_atom(app), do: Map.get(@app_keys, Atom.to_string(app))

  @doc false
  def mode_id(app, slug) when is_atom(app) and is_binary(slug), do: "#{app_key(app)}:#{slug}"

  @doc false
  def mode_slug(mode_id) when is_binary(mode_id) do
    case String.split(mode_id, ":", parts: 2) do
      [_app_key, slug] -> slug
      [slug] -> slug
    end
  end

  @doc false
  def normalize_mode_id(app, mode_id) when is_atom(app) and is_binary(mode_id) do
    case app_key(app) do
      nil ->
        mode_id

      key ->
        normalize_mode_id_for_app(app, key, mode_id)
    end
  end

  defp normalize_mode_id_for_app(app, key, mode_id) do
    cond do
      String.starts_with?(mode_id, key <> ":") ->
        mode_id

      formula_app_key?(key) and String.starts_with?(mode_id, "builtin:") ->
        slug = String.replace_prefix(mode_id, "builtin:", "")
        mode_id(app, slug)

      formula_app_key?(key) and String.starts_with?(mode_id, "user:") ->
        case Integer.parse(String.replace_prefix(mode_id, "user:", "")) do
          {id, ""} -> mode_id(app, "user_#{id}")
          _ -> mode_id
        end

      key == "collective" and not String.contains?(mode_id, ":") ->
        mode_id(app, mode_id)

      key == "matrix" and mode_id in ["matrix", "default"] ->
        mode_id(app, "matrix")

      key == "matrix" and mode_id == "matrix-ring" ->
        mode_id(app, "matrix")

      key == "perlinnoise" and mode_id in ["perlin", "default"] ->
        mode_id(app, "perlin")

      key == "ocean" and mode_id in ["ocean", "default"] ->
        mode_id(app, "ocean")

      key == "sand" and mode_id in ["sand", "default"] ->
        mode_id(app, "sand")

      key == "sparklemist" and mode_id in ["mist", "default"] ->
        mode_id(app, "mist")

      key == "wood" and mode_id in ["experiment", "default"] ->
        mode_id(app, "experiment")

      key == "fire" and mode_id in ["campfire", "default"] ->
        mode_id(app, "campfire")

      key == "gravitymask" and mode_id in ["mask", "default"] ->
        mode_id(app, "mask")

      true ->
        mode_id
    end
  end

  @doc false
  def list_presets(app) when is_atom(app) do
    app
    |> list_records()
    |> Enum.map(&to_preset(app, &1))
  end

  @doc false
  def id_for_config(app, config) when is_atom(app) do
    config = normalize_config(config)

    case Enum.find(list_presets(app), &config_matches?(app, config, &1.config)) do
      nil -> "custom"
      preset -> preset.id
    end
  end

  @doc false
  def remove_from_queue(app, mode_id) do
    normalized = normalize_mode_id(app, mode_id)

    transport = apply(@installation_transport, :get_state, [])

    new_queue = filter_queue(transport.queue, app, normalized)

    apply(@installation_transport, :set_queue, [
      Enum.map(new_queue, fn e -> %{app: e.app, mode_id: e.mode_id} end)
    ])
  end

  @doc false
  def filter_queue(queue, app, mode_id) when is_list(queue) and is_atom(app) and is_binary(mode_id) do
    normalized = normalize_mode_id(app, mode_id)

    Enum.reject(queue, fn entry ->
      entry.app == app and normalize_mode_id(app, entry.mode_id) == normalized
    end)
  end

  @doc false
  def list_modes(app) when is_atom(app) do
    app
    |> list_records()
    |> Enum.map(&to_mode_tile(app, &1))
  end

  @doc false
  def get(app, mode_id) when is_atom(app) and is_binary(mode_id) do
    mode_id = normalize_mode_id(app, mode_id)

    case fetch_record(app, mode_id) do
      nil -> nil
      record -> to_preset(app, record)
    end
  end

  @doc false
  def config_for(app, mode_id) when is_atom(app) and is_binary(mode_id) do
    case get(app, mode_id) do
      nil -> nil
      preset -> preset.config
    end
  end

  @doc false
  def summary(app, preset) when is_atom(app) do
    case app_key(app) do
      key when key in @formula_app_keys ->
        apply(app, :summary_for_preset, [preset])

      nil ->
        ""

      _key ->
        config =
          if function_exported?(app, :normalize_mode_config, 1) do
            apply(app, :normalize_mode_config, [preset.config])
          else
            preset.config
          end

        apply(app, :now_playing_meta, [config])
        |> Enum.join(" · ")
    end
  end

  @doc false
  def preset_label(app) when is_atom(app) do
    if formula_app?(app), do: "scene", else: "preset"
  end

  @doc false
  def slugify(name) when is_binary(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "_")
    |> String.trim("_")
    |> case do
      "" -> "preset"
      slug -> slug
    end
  end

  defp list_records(app), do: Loader.presets(app)

  defp fetch_record(app, mode_id) do
    fetch_record_by_slug(app, mode_slug(mode_id))
  end

  defp fetch_record_by_slug(app, slug) do
    Enum.find(list_records(app), &(&1.slug == slug))
  end

  defp to_mode_tile(app, record) do
    preset = to_preset(app, record)

    tile = %{
      id: preset.id,
      name: preset.name,
      accent_color: preset.accent_color,
      summary: summary(app, preset),
      builtin: true,
      origin: :builtin,
      deletable: false,
      renamable: false
    }

    if formula_app?(app) do
      Map.put(tile, :formula, preset.config[:program] || "")
    else
      tile
    end
  end

  defp to_preset(app, record) do
    %{
      id: mode_id(app, record.slug),
      slug: record.slug,
      name: record.name,
      config: normalize_config(record.config),
      accent_color: record.accent_color,
      origin: :builtin,
      builtin: true
    }
  end

  defp normalize_config(config) when is_map(config) do
    config
    |> atomize_config()
    |> Enum.map(fn {k, v} ->
      {k, normalize_value(v)}
    end)
    |> Map.new()
  end

  defp normalize_value(v) when is_map(v), do: normalize_config(v)
  defp normalize_value(v), do: v

  defp atomize_config(config) when is_map(config) do
    Map.new(config, fn
      {k, v} when is_binary(k) -> {String.to_existing_atom(k), normalize_value(v)}
      {k, v} when is_atom(k) -> {k, normalize_value(v)}
    end)
  rescue
    ArgumentError ->
      Map.new(config, fn {k, v} ->
        key =
          cond do
            is_atom(k) -> k
            k == "true" -> :true
            k == "false" -> :false
            true -> String.to_atom(k)
          end

        {key, normalize_value(v)}
      end)
  end

  defp config_matches?(app, config, preset_config) do
    case app_key(app) do
      "pixelfun" ->
        pixelfun_config_matches?(config, preset_config)

      "pixelfun3d" ->
        pixelfun3d_config_matches?(config, preset_config)

      _ ->
        float_eq_maps?(config, preset_config)
    end
  end

  defp pixelfun_config_matches?(config, preset_config) do
    left = pixelfun_effective_config(config)
    right = pixelfun_effective_config(preset_config)

    Enum.all?(
      [
        :program,
        :color_interval,
        :translate_scale,
        :rotate_scale,
        :zoom_scale,
        :sway_scale,
        :sway_speed,
        :sway_mode,
        :time_direction
      ],
      fn key ->
        case key do
          :program -> left.program == right.program
          :sway_mode -> left.sway_mode == right.sway_mode
          :time_direction -> left.time_direction == right.time_direction
          _ -> float_eq?(Map.get(left, key), Map.get(right, key))
        end
      end
    )
  end

  defp pixelfun3d_config_matches?(config, preset_config) do
    left = pixelfun3d_effective_config(config)
    right = pixelfun3d_effective_config(preset_config)

    keys = [
      :program,
      :color_interval,
      :palette_auto,
      :orbit_rate,
      :roll_rate,
      :roll_pivot,
      :tilt_scale,
      :tilt_speed,
      :tilt_mode,
      :elev_base,
      :zoom_base,
      :zoom_pivot,
      :pattern_speed,
      :time_direction,
      :trans_auto,
      :trans_auto_range_x,
      :trans_auto_range_y,
      :trans_auto_interval,
      :rot_auto,
      :rot_auto_range,
      :rot_auto_interval,
      :zoom_auto,
      :zoom_auto_range,
      :zoom_auto_interval,
      :sway_auto,
      :sway_auto_range,
      :sway_auto_interval,
      :sat_auto,
      :sat_auto_min,
      :sat_auto_max,
      :sat_auto_interval
    ]

    Enum.all?(keys, fn key ->
      case key do
        :program -> left.program == right.program
        :tilt_mode -> left.tilt_mode == right.tilt_mode
        :time_direction -> left.time_direction == right.time_direction
        k when k in [:trans_auto, :rot_auto, :zoom_auto, :sway_auto, :sat_auto, :palette_auto] ->
          Map.get(left, k) == Map.get(right, k)

        _ ->
          float_eq?(Map.get(left, key), Map.get(right, key))
      end
    end)
  end

  @sway_defaults %{sway_scale: 0.0, sway_speed: 0.5, sway_mode: :wobble}

  defp pixelfun_effective_config(config) do
    %{
      program: Map.get(config, :program),
      color_interval: Map.get(config, :color_interval, 5.0),
      translate_scale: Map.get(config, :translate_scale, 0.0),
      rotate_scale: Map.get(config, :rotate_scale, 0.0),
      zoom_scale: Map.get(config, :zoom_scale, 1.0),
      sway_scale: Map.get(config, :sway_scale, @sway_defaults.sway_scale),
      sway_speed: Map.get(config, :sway_speed, @sway_defaults.sway_speed),
      sway_mode: pixelfun_sway_mode(Map.get(config, :sway_mode, @sway_defaults.sway_mode)),
      time_direction: pixelfun_time_direction(Map.get(config, :time_direction, :forward))
    }
  end

  defp pixelfun3d_effective_config(config) do
    config = Octopus.Apps.PixelFun3D.migrate_legacy_config(config)

    %{
      program: Map.get(config, :program),
      color_interval: Map.get(config, :color_interval, 5.0),
      palette_auto: Map.get(config, :palette_auto, true),
      orbit_rate: Map.get(config, :orbit_rate, 0.0),
      roll_rate: Map.get(config, :roll_rate, 0.0),
      roll_pivot: Map.get(config, :roll_pivot, 0),
      tilt_scale: Map.get(config, :tilt_scale, 0.0),
      tilt_speed: Map.get(config, :tilt_speed, 0.5),
      tilt_mode: pixelfun_tilt_mode(Map.get(config, :tilt_mode, :wobble)),
      elev_base: Map.get(config, :elev_base, 0.0),
      zoom_base: Map.get(config, :zoom_base, 1.0),
      zoom_pivot: Map.get(config, :zoom_pivot, 0),
      pattern_speed: Map.get(config, :pattern_speed, 1.0),
      time_direction: pixelfun_time_direction(Map.get(config, :time_direction, :forward)),
      trans_auto: Map.get(config, :trans_auto, false),
      trans_auto_range_x: Map.get(config, :trans_auto_range_x, 1.0),
      trans_auto_range_y: Map.get(config, :trans_auto_range_y, 2.0),
      trans_auto_interval: Map.get(config, :trans_auto_interval, 30.0),
      rot_auto: Map.get(config, :rot_auto, false),
      rot_auto_range: Map.get(config, :rot_auto_range, 1.0),
      rot_auto_interval: Map.get(config, :rot_auto_interval, 30.0),
      zoom_auto: Map.get(config, :zoom_auto, false),
      zoom_auto_range: Map.get(config, :zoom_auto_range, 0.8),
      zoom_auto_interval: Map.get(config, :zoom_auto_interval, 30.0),
      sway_auto: Map.get(config, :sway_auto, false),
      sway_auto_range: Map.get(config, :sway_auto_range, 2.0),
      sway_auto_interval: Map.get(config, :sway_auto_interval, 30.0),
      sat_auto: Map.get(config, :sat_auto, false),
      sat_auto_min: Map.get(config, :sat_auto_min, 20.0),
      sat_auto_max: Map.get(config, :sat_auto_max, 100.0),
      sat_auto_interval: Map.get(config, :sat_auto_interval, 30.0)
    }
  end

  defp formula_app?(app), do: formula_app_key?(app_key(app))
  defp formula_app_key?(key) when is_binary(key), do: key in @formula_app_keys
  defp formula_app_key?(_), do: false

  defp pixelfun_sway_mode(:wobble), do: :wobble
  defp pixelfun_sway_mode(:pendulum), do: :pendulum
  defp pixelfun_sway_mode("wobble"), do: :wobble
  defp pixelfun_sway_mode("pendulum"), do: :pendulum
  defp pixelfun_sway_mode(_), do: :wobble

  defp pixelfun_tilt_mode(:wobble), do: :wobble
  defp pixelfun_tilt_mode(:pendulum), do: :pendulum
  defp pixelfun_tilt_mode("wobble"), do: :wobble
  defp pixelfun_tilt_mode("pendulum"), do: :pendulum
  defp pixelfun_tilt_mode(_), do: :wobble

  defp pixelfun_time_direction(:forward), do: :forward
  defp pixelfun_time_direction(:backward), do: :backward
  defp pixelfun_time_direction("forward"), do: :forward
  defp pixelfun_time_direction("backward"), do: :backward
  defp pixelfun_time_direction(_), do: :forward

  defp float_eq_maps?(left, right) do
    Map.keys(left) == Map.keys(right) &&
      Enum.all?(left, fn {k, v} -> float_eq?(v, Map.get(right, k)) end)
  end

  defp float_eq?(a, b) when is_number(a) and is_number(b), do: abs(a - b) < 0.001
  defp float_eq?(a, b), do: a == b
end
