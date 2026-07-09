defmodule Octopus.Hardware.PanelStatusTracker do
  @moduledoc """
  Tracks panel online/stale/offline status and broadcasts changes on PubSub.

  Status is derived from `FirmwareInfo` heartbeats stored by `Octopus.Broadcaster`.
  A periodic check detects stale/offline transitions when heartbeats stop arriving.
  LiveViews and other consumers should subscribe via `Octopus.Hardware.PanelStatus`
  rather than polling.
  """

  use GenServer

  require Logger

  alias Octopus.Hardware.PanelStatus

  @check_interval 2_000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Notifies the tracker that a `FirmwareInfo` packet was received.
  """
  @spec firmware_info_received(term(), term()) :: :ok
  def firmware_info_received(firmware_info, from_ip) do
    GenServer.cast(__MODULE__, {:firmware_info, firmware_info, from_ip})
  end

  @impl true
  def init(_opts) do
    if PanelStatus.enabled?() do
      schedule_check()
    end

    {:ok, %{statuses: %{}}}
  end

  @impl true
  def handle_cast({:firmware_info, _firmware_info, _from_ip}, state) do
    {:noreply, reconcile(state)}
  end

  @impl true
  def handle_info(:check, state) do
    schedule_check()
    {:noreply, reconcile(state)}
  end

  defp schedule_check do
    Process.send_after(self(), :check, @check_interval)
  end

  defp reconcile(%{statuses: previous} = state) do
    if PanelStatus.enabled?() do
      current = PanelStatus.all()

      current_by_panel = Map.new(current, &{&1.panel, &1})

      Enum.each(current, fn %{panel: panel, status: status, controller_id: controller_id} ->
        case Map.get(previous, panel) do
          ^status ->
            :ok

          prev ->
            Logger.info(
              "[panel_status] panel #{panel} (#{controller_id}): #{prev || "unknown"} -> #{status}"
            )

            PanelStatus.broadcast_change(panel, status)
        end
      end)

      %{state | statuses: Map.new(current_by_panel, fn {panel, entry} -> {panel, entry.status} end)}
    else
      state
    end
  end
end
