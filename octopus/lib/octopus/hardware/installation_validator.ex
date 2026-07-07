defmodule Octopus.Hardware.InstallationValidator do
  @moduledoc """
  Validates installation panel configuration against the hardware catalog.
  """

  require Logger

  alias Octopus.Hardware
  alias Octopus.Hardware.{Controller, PanelSlot, Wiring}

  defmodule Error do
    defexception [:message]
  end

  @broadcast_pixel_limit 768

  @doc """
  Validates installation options against the controller and wiring registries.

  Raises `InstallationValidator.Error` on invalid configuration.
  Logs warnings for broadcast frame size limits.
  """
  @spec validate!(keyword(), %{atom() => Controller.t()}) :: :ok
  def validate!(installation_opts, controller_registry \\ Hardware.registry()) do
    panel_slots = Keyword.get(installation_opts, :panel_slots)

    if panel_slots do
      wiring_registry = Hardware.wiring_registry()
      validate_panel_slots!(panel_slots, installation_opts, controller_registry, wiring_registry)
    end

    :ok
  end

  defp validate_panel_slots!(panel_slots, installation_opts, controller_registry, wiring_registry) do
    for %PanelSlot{controller_id: controller_id, wiring_id: wiring_id} <- panel_slots do
      unless Map.has_key?(controller_registry, controller_id) do
        raise Error,
              message:
                "unknown controller id #{inspect(controller_id)} in installation panels list; not in hardware catalog"
      end

      unless Map.has_key?(wiring_registry, wiring_id) do
        raise Error,
              message:
                "unknown wiring id #{inspect(wiring_id)} in installation panels list; not in wiring catalog"
      end
    end

    panel_layout = Keyword.get(installation_opts, :panel_layout, {8, 8})

    for %PanelSlot{wiring_id: wiring_id} <- panel_slots do
      %Wiring{matrix: wiring_matrix} = Map.fetch!(wiring_registry, wiring_id)

      unless wiring_matrix == panel_layout do
        raise Error,
              message:
                "wiring #{inspect(wiring_id)} matrix #{inspect(wiring_matrix)} does not match installation panel_layout #{inspect(panel_layout)}"
      end
    end

    network_config = Keyword.get(installation_opts, :network_config, [])
    mode = Keyword.get(network_config, :mode, :broadcast)

    duplicate_firmware_indices(panel_slots, controller_registry)
    |> validate_duplicate_indices!(mode, length(panel_slots))

    maybe_warn_broadcast_frame_size(panel_slots, controller_registry, mode)

    :ok
  end

  defp duplicate_firmware_indices(panel_slots, controller_registry) do
    panel_slots
    |> Enum.map(fn %PanelSlot{controller_id: id} -> Map.fetch!(controller_registry, id) end)
    |> Enum.group_by(& &1.firmware_panel_index)
    |> Enum.filter(fn {_index, entries} -> length(entries) > 1 end)
  end

  defp validate_duplicate_indices!([], _mode, _num_panels), do: :ok

  defp validate_duplicate_indices!(duplicates, :broadcast, _num_panels) do
    {index, controllers} = hd(duplicates)

    ids = Enum.map(controllers, & &1.id)

    raise Error,
          message:
            "broadcast installation cannot include multiple panels with firmware_panel_index #{index}: #{Enum.map_join(ids, ", ", &inspect/1)}"
  end

  defp validate_duplicate_indices!(duplicates, :individual, num_panels) when num_panels > 1 do
    {index, controllers} = hd(duplicates)
    ids = Enum.map(controllers, & &1.id)

    raise Error,
          message:
            "individual installation with #{num_panels} panels cannot include duplicate firmware_panel_index #{index}: #{Enum.map_join(ids, ", ", &inspect/1)}"
  end

  defp validate_duplicate_indices!(_duplicates, :individual, _num_panels), do: :ok

  defp maybe_warn_broadcast_frame_size(panel_slots, controller_registry, :broadcast) do
    max_index =
      panel_slots
      |> Enum.map(fn %PanelSlot{controller_id: id} -> Map.fetch!(controller_registry, id).firmware_panel_index end)
      |> Enum.max(fn -> 0 end)

    pixel_count =
      panel_slots
      |> Enum.map(fn %PanelSlot{controller_id: id} -> Map.fetch!(controller_registry, id).pixel_count end)
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

  defp maybe_warn_broadcast_frame_size(_panel_slots, _controller_registry, _mode), do: :ok
end
