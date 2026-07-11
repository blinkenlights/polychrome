defmodule Octopus.Hardware.PanelStatus do
  @moduledoc """
  Derives per-panel online/stale/offline status from firmware heartbeat packets.

  Controllers send `FirmwareInfo` every 5 seconds. Thresholds are tuned to ~2×
  and ~6× that interval for online and offline boundaries.
  """

  alias Octopus.Broadcaster
  alias Octopus.Broadcaster.FirmwareInfoMeta
  alias Octopus.Hardware
  alias Octopus.Hardware.{Controller, PanelSlot}
  alias Octopus.Installation

  @online_threshold 10
  @stale_threshold 30

  @type status :: :online | :stale | :offline

  @type panel_status :: %{
          panel: pos_integer(),
          status: status(),
          last_seen: non_neg_integer() | nil,
          controller_id: atom(),
          firmware_info: Octopus.Protobuf.FirmwareInfo.t() | nil
        }

  @doc """
  Returns whether panel status tracking is active.

  Mirrors runtime UDP sending — disabled when output to hardware is off.
  """
  @spec enabled?() :: boolean()
  def enabled?, do: Broadcaster.sending_enabled?()

  @doc "Global PubSub topic for panel status changes."
  @spec topic() :: String.t()
  def topic, do: "hardware:panel_status"

  @doc "PubSub topic for status changes of a single panel (1-based)."
  @spec topic(pos_integer()) :: String.t()
  def topic(panel) when is_integer(panel) and panel >= 1, do: "#{topic()}:#{panel}"

  @doc "Subscribe to all panel status changes."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: Phoenix.PubSub.subscribe(Octopus.PubSub, topic())

  @doc "Subscribe to status changes for a single panel."
  @spec subscribe(pos_integer()) :: :ok | {:error, term()}
  def subscribe(panel), do: Phoenix.PubSub.subscribe(Octopus.PubSub, topic(panel))

  @doc "Broadcast a panel status change."
  @spec broadcast_change(pos_integer(), status()) :: :ok
  def broadcast_change(panel, status) do
    message = {:panel_status, panel, status}

    Phoenix.PubSub.broadcast(Octopus.PubSub, topic(), message)
    Phoenix.PubSub.broadcast(Octopus.PubSub, topic(panel), message)
  end

  @doc """
  Returns status for all installation panel slots (1-based panel numbers).
  """
  @spec all() :: [panel_status()]
  def all, do: all(System.os_time(:second), [])

  @spec all(non_neg_integer(), keyword()) :: [panel_status()]
  def all(now, opts) when is_integer(now) and is_list(opts) do
    firmware_stats = Keyword.get_lazy(opts, :firmware_stats, &Broadcaster.firmware_stats/0)
    panel_slots = Keyword.get_lazy(opts, :panel_slots, &Installation.panel_slots/0)

    panel_slots
    |> Enum.with_index(1)
    |> Enum.map(fn {%PanelSlot{controller_id: controller_id}, panel} ->
      controller = Hardware.fetch!(controller_id)
      meta = find_firmware_meta(firmware_stats, controller)

      %{
        panel: panel,
        status: status_for_last_seen(meta && meta.last_seen, now),
        last_seen: meta && meta.last_seen,
        controller_id: controller_id,
        firmware_info: meta && meta.firmware_info
      }
    end)
  end

  @doc """
  Maps seconds since last heartbeat to a status atom.
  """
  @spec status_for_age(non_neg_integer() | nil) :: status()
  def status_for_age(nil), do: :offline
  def status_for_age(age) when is_integer(age), do: status_for_age_seconds(age)

  @spec status_for_last_seen(non_neg_integer() | nil, non_neg_integer()) :: status()
  def status_for_last_seen(nil, _now), do: :offline

  def status_for_last_seen(last_seen, now) when is_integer(last_seen) and is_integer(now) do
    age = now - last_seen
    status_for_age_seconds(age)
  end

  @spec status_for_age_seconds(non_neg_integer()) :: status()
  def status_for_age_seconds(age) when age <= @online_threshold, do: :online
  def status_for_age_seconds(age) when age <= @stale_threshold, do: :stale
  def status_for_age_seconds(_age), do: :offline

  defp find_firmware_meta(firmware_stats, %Controller{} = controller) do
    firmware_stats
    |> Map.values()
    |> Enum.find(fn %FirmwareInfoMeta{firmware_info: info} ->
      macs_match?(info.mac, controller.mac) or
        hostnames_match?(info.hostname, controller.hostname)
    end)
  end

  defp macs_match?(left, right) when is_binary(left) and is_binary(right) do
    String.downcase(left) == String.downcase(right)
  end

  defp macs_match?(_, _), do: false

  defp hostnames_match?(left, right) when is_binary(left) and is_binary(right) do
    normalize_hostname(left) == normalize_hostname(right)
  end

  defp hostnames_match?(_, _), do: false

  defp normalize_hostname(hostname) do
    hostname
    |> String.downcase()
    |> String.trim_trailing(".local")
  end
end
