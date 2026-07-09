defmodule Octopus.AppModePresets do
  @moduledoc """
  DB-backed mode presets for foyer apps (Pixel Fun, Collective, Matrix, Perlin Noise, Ocean, Sand, Sparkle Mist).

  Mode ids use `app_key:slug`, e.g. `pixelfun:classic_ripple`, `collective:storm`.
  Legacy Pixel Fun ids (`builtin:…`, `user:…`) and bare Collective slugs are
  accepted via `normalize_mode_id/2`.
  """

  import Ecto.Query, only: [order_by: 2, where: 3]

  alias Octopus.App
  alias Octopus.AppModePreset
  alias Octopus.Apps.{Collective, Matrix, Ocean, PerlinNoise, PixelFun, Sand, SparkleMist}
  alias Octopus.Apps.PixelFun.Program
  alias Octopus.Repo

  @persistable [PixelFun, Collective, Matrix, PerlinNoise, Ocean, Sand, SparkleMist]

  @app_keys %{
    PixelFun => "pixelfun",
    Collective => "collective",
    Matrix => "matrix",
    PerlinNoise => "perlinnoise",
    Ocean => "ocean",
    Sand => "sand",
    SparkleMist => "sparklemist"
  }

  @doc false
  def persistable_apps, do: @persistable

  @doc false
  def persistable?(app) when app in @persistable, do: true
  def persistable?(_), do: false

  @doc false
  def app_key(app) when is_atom(app) do
    case Map.fetch(@app_keys, app) do
      {:ok, key} -> key
      :error -> nil
    end
  end

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

      app == PixelFun and String.starts_with?(mode_id, "builtin:") ->
        slug = String.replace_prefix(mode_id, "builtin:", "")
        mode_id(app, slug)

      app == PixelFun and String.starts_with?(mode_id, "user:") ->
        case Integer.parse(String.replace_prefix(mode_id, "user:", "")) do
          {id, ""} -> mode_id(app, "user_#{id}")
          _ -> mode_id
        end

      app == Collective and not String.contains?(mode_id, ":") ->
        mode_id(app, mode_id)

      app == Matrix and mode_id in ["matrix", "default"] ->
        mode_id(app, "matrix")

      app == PerlinNoise and mode_id in ["perlin", "default"] ->
        mode_id(app, "perlin")

      app == Ocean and mode_id in ["ocean", "default"] ->
        mode_id(app, "ocean")

      app == Sand and mode_id in ["sand", "default"] ->
        mode_id(app, "sand")

      app == SparkleMist and mode_id in ["mist", "default"] ->
        mode_id(app, "mist")

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

    transport = Octopus.InstallationTransport.get_state()

    new_queue = filter_queue(transport.queue, app, normalized)

    Octopus.InstallationTransport.set_queue(
      Enum.map(new_queue, fn e -> %{app: e.app, mode_id: e.mode_id} end)
    )
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
  def create(app, name, config, opts \\ []) when is_atom(app) and is_binary(name) do
    config = normalize_config(config)
    accent_color = Keyword.get(opts, :accent_color, random_accent_color())

    with :ok <- validate_config(app, config) do
      slug = unique_slug(app, slugify(name))

      %AppModePreset{}
      |> AppModePreset.changeset(%{
        app: module_name(app),
        slug: slug,
        name: String.trim(name),
        config: config,
        accent_color: accent_color,
        origin: "user"
      })
      |> Repo.insert()
      |> case do
        {:ok, record} -> {:ok, to_preset(app, record)}
        error -> error
      end
    end
  end

  @doc false
  def update(app, mode_id, attrs) when is_atom(app) and is_binary(mode_id) do
    mode_id = normalize_mode_id(app, mode_id)

    with %AppModePreset{} = record <- fetch_record(app, mode_id) do
      attrs = normalize_update_attrs(app, attrs)

      config =
        record.config
        |> normalize_config()
        |> Map.merge(Map.get(attrs, :config, %{}))

      attrs = Map.put(attrs, :config, config)

      with :ok <- validate_config(app, config) do
        record
        |> AppModePreset.changeset(attrs)
        |> Repo.update()
        |> case do
          {:ok, updated} -> {:ok, to_preset(app, updated)}
          error -> error
        end
      end
    else
      nil -> {:error, :not_found}
    end
  end

  @doc false
  def rename(app, mode_id, name) when is_atom(app) and is_binary(mode_id) and is_binary(name) do
    update(app, mode_id, %{name: String.trim(name)})
  end

  @doc false
  def archive(app, mode_id) when is_atom(app) and is_binary(mode_id) do
    mode_id = normalize_mode_id(app, mode_id)

    case fetch_record(app, mode_id) do
      nil ->
        {:error, :not_found}

      record ->
        record
        |> AppModePreset.changeset(%{archived_at: DateTime.utc_now() |> DateTime.truncate(:second)})
        |> Repo.update()
        |> case do
          {:ok, _} -> :ok
          {:error, _} -> {:error, :failed}
        end
    end
  end

  @doc false
  def sync_builtins(app) when is_atom(app) do
    app
    |> builtin_presets()
    |> Enum.each(fn builtin ->
      slug = builtin.slug

      case fetch_record_by_slug(app, slug) do
        nil ->
          %AppModePreset{}
          |> AppModePreset.changeset(%{
            app: module_name(app),
            slug: slug,
            name: builtin.name,
            config: normalize_config(builtin.config),
            accent_color: builtin.accent_color,
            origin: "builtin"
          })
          |> Repo.insert()

        _ ->
          :ok
      end
    end)

    :ok
  end

  @doc false
  def sync_all! do
    Enum.each(@persistable, &sync_builtins/1)
    :ok
  end

  @doc false
  def attrs_from_effective(app, mode_id, effective) when is_atom(app) do
    effective = normalize_config(effective)
    mode_id = normalize_mode_id(app, mode_id)
    slug = mode_slug(mode_id)

    base =
      app
      |> legacy_mode_config(slug)
      |> Map.merge(App.mode_config(app, mode_id))

    keys =
      (Map.keys(base) ++ tweakable_keys(app, mode_id))
      |> Enum.uniq()

    config = Map.take(effective, keys)

    case app do
      PixelFun ->
        %{
          config: config,
          name: nil,
          accent_color: random_accent_color(),
          formula: config[:program]
        }

      _ ->
        %{config: config, name: nil, accent_color: random_accent_color()}
    end
  end

  @doc false
  def summary(app, preset) when is_atom(app) do
    case app do
      PixelFun ->
        PixelFun.summary_for_preset(preset)

      app ->
        config = summary_config(app, preset)

        app
        |> App.now_playing_meta(config)
        |> Enum.join(" · ")
    end
  end

  @doc false
  def preset_label(PixelFun), do: "scene"
  def preset_label(_), do: "preset"

  @doc false
  def random_accent_color do
    <<r, g, b>> = :crypto.strong_rand_bytes(3)
    "#" <> Base.encode16(<<r, g, b>>, case: :upper)
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

  defp summary_config(app, preset) do
    case app do
      Collective -> Collective.normalize_mode_config(preset.config)
      Sand -> Sand.normalize_mode_config(preset.config)
      SparkleMist -> SparkleMist.normalize_mode_config(preset.config)
      _ -> preset.config
    end
  end

  defp list_records(app) do
    AppModePreset
    |> where([p], p.app == ^module_name(app) and is_nil(p.archived_at))
    |> order_by(asc: :name)
    |> Repo.all()
  end

  defp fetch_record(app, mode_id) do
    fetch_record_by_slug(app, mode_slug(mode_id))
  end

  defp fetch_record_by_slug(app, slug) do
    AppModePreset
    |> where([p], p.app == ^module_name(app) and p.slug == ^slug and is_nil(p.archived_at))
    |> Repo.one()
  end

  defp to_mode_tile(app, record) do
    preset = to_preset(app, record)

    tile = %{
      id: preset.id,
      name: preset.name,
      accent_color: preset.accent_color,
      summary: summary(app, preset),
      builtin: preset.origin == :builtin,
      origin: preset.origin,
      deletable: true,
      renamable: true
    }

    case app do
      PixelFun -> Map.put(tile, :formula, preset.config[:program] || "")
      _ -> tile
    end
  end

  defp to_preset(app, %AppModePreset{} = record) do
    %{
      id: mode_id(app, record.slug),
      slug: record.slug,
      name: record.name,
      config: atomize_config(record.config),
      accent_color: record.accent_color,
      origin: String.to_existing_atom(record.origin),
      builtin: record.origin == "builtin",
      db_id: record.id
    }
  end

  defp normalize_update_attrs(app, attrs) do
    attrs =
      if Map.has_key?(attrs, :config) do
        Map.put(attrs, :config, normalize_config(attrs.config))
      else
        attrs
      end

    case app do
      PixelFun ->
        config = Map.get(attrs, :config, %{})

        attrs
        |> Map.put(:config, maybe_put_program_from_formula(config, attrs))
        |> Map.drop([:formula, :program])

      _ ->
        Map.drop(attrs, [:formula, :program])
    end
  end

  defp maybe_put_program_from_formula(config, attrs) do
    formula = Map.get(attrs, :formula) || Map.get(attrs, :program)

    if is_binary(formula) do
      Map.put(config, :program, formula)
    else
      config
    end
  end

  defp unique_slug(app, base) do
    if fetch_record_by_slug(app, base), do: next_slug(app, base, 2), else: base
  end

  defp next_slug(app, base, n) do
    slug = "#{base}_#{n}"
    if fetch_record_by_slug(app, slug), do: next_slug(app, base, n + 1), else: slug
  end

  defp validate_config(PixelFun, config) do
    case validate_formula(Map.get(config, :program, "")) do
      :ok -> :ok
      :error -> {:error, :invalid_formula}
    end
  end

  defp validate_config(_app, _config), do: :ok

  defp validate_formula(formula) when is_binary(formula) do
    case Program.parse(formula) do
      {:ok, _} -> :ok
      _ -> :error
    end
  end

  defp tweakable_keys(app, mode_id) do
    app
    |> App.mode_tweakables(mode_id)
    |> Enum.map(& &1.key)
  end

  defp module_name(app), do: Atom.to_string(app)

  defp builtin_presets(app) do
    apply(app, :builtin_presets, [])
  end

  defp legacy_mode_config(app, slug) do
    case app do
      Collective -> Collective.legacy_mode_config(slug)
      Matrix -> Matrix.legacy_mode_config(slug)
      PerlinNoise -> PerlinNoise.legacy_mode_config(slug)
      Ocean -> Ocean.legacy_mode_config(slug)
      Sand -> Sand.legacy_mode_config(slug)
      SparkleMist -> SparkleMist.legacy_mode_config(slug)
      PixelFun -> PixelFun.legacy_mode_config(slug)
      _ -> %{}
    end
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

  defp config_matches?(PixelFun, config, preset_config) do
    Enum.all?(
      [:program, :color_interval, :translate_scale, :rotate_scale, :zoom_scale],
      fn key -> float_eq?(Map.get(config, key), Map.get(preset_config, key)) end
    )
  end

  defp config_matches?(_app, config, preset_config) do
    float_eq_maps?(config, preset_config)
  end

  defp float_eq_maps?(left, right) do
    Map.keys(left) == Map.keys(right) &&
      Enum.all?(left, fn {k, v} -> float_eq?(v, Map.get(right, k)) end)
  end

  defp float_eq?(a, b) when is_number(a) and is_number(b), do: abs(a - b) < 0.001
  defp float_eq?(a, b), do: a == b
end
