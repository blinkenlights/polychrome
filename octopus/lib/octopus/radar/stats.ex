defmodule Octopus.Radar.Stats do
  @moduledoc """
  In-memory operational statistics for radar sensors, accumulated from
  process startup (not persisted across restarts).

  Subscribes to the per-sensor status PubSub topics — the same source used
  by `Octopus.Radar.StatusHistory` — and folds every transition into a set
  of running counters per device:

    * total tracked time (since startup)
    * total and average time spent in each status
    * dropouts — how many times continuous operation was lost
    * retries — how many recovery attempts were made to re-instate operation

  ## Semantics (tunable)

    * A **dropout** is counted each time a sensor leaves `:working` for any
      non-working status after having been `:working`.
    * A **retry** is counted for each active recovery attempt — i.e. each
      entry into `:initializing` or `:probing` — that happens while an outage
      is active (after a dropout, before the sensor returns to `:working`).
      Initial bring-up before the sensor has ever worked is not counted.

  These are derived purely from the observable status transitions; the
  sensor's internal command-level retries are intentionally not counted.

  Consumers call `get_all/0` for a snapshot in which the in-progress current
  status duration is folded into the per-status totals and a `total_ms`
  (wall-clock time since the device started being tracked) is included.
  """

  use GenServer

  alias Octopus.Radar

  @recovery_statuses [:initializing, :probing]

  ## Client API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Return a snapshot of statistics for all tracked devices.

  Shape: `%{device_id => stats}` where `stats` is a map with keys
  `:total_ms`, `:durations` (`%{status => ms}`), `:entries`
  (`%{status => count}`), `:dropouts`, `:retries`, and `:current_status`.
  The current status's in-progress duration is included in `:durations`.
  """
  @spec get_all() :: %{pos_integer() => map()}
  def get_all do
    GenServer.call(__MODULE__, :get_all)
  end

  @doc "Reset all counters, re-seeding from each sensor's current status."
  @spec reset() :: :ok
  def reset do
    GenServer.call(__MODULE__, :reset)
  end

  ## GenServer callbacks

  @impl true
  def init(_opts) do
    {:ok, %{}, {:continue, :subscribe}}
  end

  @impl true
  def handle_continue(:subscribe, _state) do
    if Radar.configured?() do
      devices = Radar.devices()
      Enum.each(devices, &Radar.subscribe_status(&1.device_id))

      now = System.system_time(:millisecond)

      stats =
        Map.new(devices, fn d ->
          status = Radar.sensor_status(d.device_id)
          {d.device_id, new_sensor_stats(status, now)}
        end)

      {:noreply, stats}
    else
      {:noreply, %{}}
    end
  end

  @impl true
  def handle_call(:get_all, _from, stats) do
    now = System.system_time(:millisecond)
    {:reply, Map.new(stats, fn {id, s} -> {id, snapshot(s, now)} end), stats}
  end

  def handle_call(:reset, _from, stats) do
    now = System.system_time(:millisecond)

    reset_stats =
      Map.new(stats, fn {id, s} -> {id, new_sensor_stats(s.current_status, now)} end)

    {:reply, :ok, reset_stats}
  end

  @impl true
  def handle_info({:radar_sensor_status, device_id, status}, stats) do
    now = System.system_time(:millisecond)
    current = Map.get(stats, device_id) || new_sensor_stats(status, now)
    {:noreply, Map.put(stats, device_id, apply_transition(current, status, now))}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  ## Private helpers

  defp new_sensor_stats(status, now) do
    %{
      started_at: now,
      current_status: status,
      since: now,
      durations: %{},
      entries: %{status => 1},
      dropouts: 0,
      retries: 0,
      outage_active?: false
    }
  end

  # A repeat broadcast of the same status carries no transition; ignore it so
  # the per-status duration keeps accruing against the original entry.
  defp apply_transition(%{current_status: status} = stats, status, _now), do: stats

  defp apply_transition(stats, status, now) do
    old = stats.current_status
    elapsed = max(now - stats.since, 0)

    durations = Map.update(stats.durations, old, elapsed, &(&1 + elapsed))
    entries = Map.update(stats.entries, status, 1, &(&1 + 1))

    dropout? = old == :working and status != :working
    outage_active? = cond do
      status == :working -> false
      dropout? -> true
      true -> stats.outage_active?
    end

    dropouts = if dropout?, do: stats.dropouts + 1, else: stats.dropouts

    retries =
      if outage_active? and status in @recovery_statuses do
        stats.retries + 1
      else
        stats.retries
      end

    %{
      stats
      | current_status: status,
        since: now,
        durations: durations,
        entries: entries,
        dropouts: dropouts,
        retries: retries,
        outage_active?: outage_active?
    }
  end

  defp snapshot(stats, now) do
    elapsed = max(now - stats.since, 0)
    durations = Map.update(stats.durations, stats.current_status, elapsed, &(&1 + elapsed))

    %{
      total_ms: max(now - stats.started_at, 0),
      durations: durations,
      entries: stats.entries,
      dropouts: stats.dropouts,
      retries: stats.retries,
      current_status: stats.current_status
    }
  end
end
