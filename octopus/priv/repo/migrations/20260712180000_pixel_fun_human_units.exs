defmodule Octopus.Repo.Migrations.PixelFunHumanUnits do
  use Ecto.Migration

  # Nation2026 circular ring width: 12 panels * (8 + 18) = 312.
  # migrate_legacy_config/1 uses Installation.width() (fallback 312).
  @installation_width_nation2026 312

  def up do
    _ = @installation_width_nation2026
    flush()

    import Ecto.Query

    rows =
      Octopus.Repo.all(
        from p in "app_mode_presets",
          where: p.app in ["pixelfun", "Octopus.Apps.PixelFun"],
          select: {p.id, p.config}
      )

    Enum.each(rows, fn {id, config} ->
      config =
        config
        |> decode_config()
        |> atomize_keys()
        |> Map.drop([:pixel_fun_units])
        |> Map.put(:legacy_internal_units, true)

      migrated =
        config
        |> Octopus.Apps.PixelFun.migrate_legacy_config()
        |> encode_config()

      Octopus.Repo.update_all(
        from(p in "app_mode_presets", where: p.id == ^id),
        set: [config: migrated, updated_at: DateTime.utc_now() |> DateTime.truncate(:second)]
      )
    end)
  end

  def down, do: :ok

  # Raw SQLite queries return :map columns as JSON text (no Ecto type load).
  defp decode_config(config) when is_binary(config) do
    case Jason.decode(config) do
      {:ok, map} when is_map(map) -> map
      _ -> %{}
    end
  end

  defp decode_config(%{} = config), do: config
  defp decode_config(_), do: %{}

  defp encode_config(config) when is_map(config) do
    config
    |> Map.new(fn {k, v} -> {to_string(k), stringify_nested(v)} end)
    |> Jason.encode!()
  end

  defp stringify_nested(%{} = map), do: Map.new(map, fn {k, v} -> {to_string(k), stringify_nested(v)} end)
  defp stringify_nested(list) when is_list(list), do: Enum.map(list, &stringify_nested/1)
  defp stringify_nested(v), do: v

  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_binary(k) -> {String.to_atom(k), atomize_keys(v)}
      {k, v} -> {k, atomize_keys(v)}
    end)
  rescue
    ArgumentError ->
      Map.new(map, fn
        {k, v} when is_binary(k) -> {String.to_atom(k), atomize_keys(v)}
        {k, v} -> {k, atomize_keys(v)}
      end)
  end

  defp atomize_keys(v), do: v
end
