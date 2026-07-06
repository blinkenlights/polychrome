defmodule Octopus.Hardware.InstallationValidator do
  @moduledoc """
  Validates installation panel configuration against the hardware catalog.
  """

  require Logger

  alias Octopus.Hardware
  alias Octopus.Hardware.Panel

  defmodule Error do
    defexception [:message]
  end

  @broadcast_pixel_limit 768

  @doc """
  Validates installation options against the panel registry.

  Raises `InstallationValidator.Error` on invalid configuration.
  Logs warnings for broadcast frame size limits.
  """
  @spec validate!(keyword(), %{atom() => Panel.t()}) :: :ok
  def validate!(installation_opts, panel_registry \\ Hardware.registry()) do
    panels = Keyword.get(installation_opts, :panels)

    if panels do
      validate_panels!(panels, installation_opts, panel_registry)
    end

    :ok
  end

  defp validate_panels!(panels, installation_opts, panel_registry) do
    for panel_id <- panels do
      unless Map.has_key?(panel_registry, panel_id) do
        raise Error,
              message:
                "unknown panel id #{inspect(panel_id)} in installation panels list; not in hardware catalog"
      end
    end

    network_config = Keyword.get(installation_opts, :network_config, [])
    mode = Keyword.get(network_config, :mode, :broadcast)

    duplicate_firmware_indices(panels, panel_registry)
    |> validate_duplicate_indices!(mode, length(panels))

    maybe_warn_broadcast_frame_size(panels, panel_registry, mode, installation_opts)

    :ok
  end

  defp duplicate_firmware_indices(panels, panel_registry) do
    panels
    |> Enum.map(&Map.fetch!(panel_registry, &1))
    |> Enum.group_by(& &1.firmware_panel_index)
    |> Enum.filter(fn {_index, entries} -> length(entries) > 1 end)
  end

  defp validate_duplicate_indices!([], _mode, _num_panels), do: :ok

  defp validate_duplicate_indices!(duplicates, :broadcast, _num_panels) do
    {index, panels} = hd(duplicates)

    ids = Enum.map(panels, & &1.id)

    raise Error,
          message:
            "broadcast installation cannot include multiple panels with firmware_panel_index #{index}: #{Enum.map_join(ids, ", ", &inspect/1)}"
  end

  defp validate_duplicate_indices!(duplicates, :individual, num_panels) when num_panels > 1 do
    {index, panels} = hd(duplicates)
    ids = Enum.map(panels, & &1.id)

    raise Error,
          message:
            "individual installation with #{num_panels} panels cannot include duplicate firmware_panel_index #{index}: #{Enum.map_join(ids, ", ", &inspect/1)}"
  end

  defp validate_duplicate_indices!(_duplicates, :individual, _num_panels), do: :ok

  defp maybe_warn_broadcast_frame_size(panels, panel_registry, :broadcast, _installation_opts) do
    max_index =
      panels
      |> Enum.map(&Map.fetch!(panel_registry, &1).firmware_panel_index)
      |> Enum.max(fn -> 0 end)

    pixel_count =
      panels
      |> Enum.map(&Map.fetch!(panel_registry, &1).pixel_count)
      |> Enum.max(fn -> 64 end)

    required_pixels = max_index * pixel_count

    if required_pixels > @broadcast_pixel_limit do
      Logger.warning(
        "Installation broadcast frame requires #{required_pixels} pixels " <>
          "(max firmware_panel_index #{max_index} × #{pixel_count}) " <>
          "but protocol limit is #{@broadcast_pixel_limit} pixels (12 panels). " <>
          "Use individual mode or reduce panel count."
      )
    end
  end

  defp maybe_warn_broadcast_frame_size(_panels, _panel_registry, _mode, _installation_opts), do: :ok
end
