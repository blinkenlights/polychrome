defmodule Octopus.AppModePresets.LoaderSupport do
  @moduledoc false

  alias Octopus.Apps.PixelFun.Program

  @formula_app_keys ~w(pixelfun pixelfun3d)

  def load_file(path, app_key) do
    path
    |> File.read!()
    |> Jason.decode!()
    |> build_presets(app_key)
  end

  def build_presets(%{"presets" => entries}, app_key) when is_list(entries) do
    entries
    |> Enum.map(&build_preset(&1, app_key))
    |> Enum.sort_by(& &1.name)
  end

  def build_presets(other, app_key) do
    raise ArgumentError,
          "invalid preset file for #{app_key}: expected {\"presets\": [...]}, got #{inspect(other)}"
  end

  defp build_preset(
         %{"slug" => slug, "name" => name, "accent_color" => accent_color, "config" => config},
         app_key
       )
       when is_binary(slug) and is_binary(name) and is_binary(accent_color) and is_map(config) do
    config = atomize_config(config)
    validate_formula!(app_key, slug, config)

    %{
      slug: slug,
      name: name,
      accent_color: accent_color,
      config: config,
      origin: :builtin
    }
  end

  defp build_preset(entry, app_key) do
    raise ArgumentError, "invalid preset entry in #{app_key}: #{inspect(entry)}"
  end

  defp validate_formula!(app_key, slug, config) when app_key in @formula_app_keys do
    formula = Map.get(config, :program, "")

    case Program.parse(formula) do
      {:ok, _} ->
        :ok

      _ ->
        raise ArgumentError,
              "invalid formula in priv/app_mode_presets/#{app_key}/#{app_key}-settings.json preset #{slug}: #{inspect(formula)}"
    end
  end

  defp validate_formula!(_app_key, _slug, _config), do: :ok

  defp atomize_config(config) when is_map(config) do
    Map.new(config, fn
      {k, v} when is_binary(k) -> {String.to_existing_atom(k), atomize_value(v)}
      {k, v} when is_atom(k) -> {k, atomize_value(v)}
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

        {key, atomize_value(v)}
      end)
  end

  defp atomize_value("true"), do: true
  defp atomize_value("false"), do: false
  defp atomize_value(v) when is_map(v), do: atomize_config(v)

  defp atomize_value(v) when is_binary(v) do
    if String.match?(v, ~r/^[a-z][a-z0-9_]*$/) do
      try do
        String.to_existing_atom(v)
      rescue
        ArgumentError -> v
      end
    else
      v
    end
  end

  defp atomize_value(v), do: v
end
