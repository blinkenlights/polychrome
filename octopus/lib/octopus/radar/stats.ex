defmodule Octopus.Radar.Stats do
  @moduledoc """
  Operational statistics for radar sensors, persisted across restarts.

  Subscribes to the per-sensor status PubSub topics — the same source used
  by `Octopus.Radar.StatusHistory` — and folds every transition into a set
  of running counters per device:

    * total tracked time (since first ever recorded event)
    * total and average time spent in each status
    * dropouts — how many times continuous operation was lost
    * retries — how many recovery attempts were made to re-instate operation

  ## Persistence

  Every genuine status change is written to the `radar_sensor_transitions`
  database table via `Octopus.Radar.SensorTransition`.  On startup the full
  history is replayed to reconstruct lifetime counters before the current
  session's events begin accumulating.  The time gap between the last
  persisted event and the new session is intentionally not attributed to any
  status (we cannot know how long the service was offline).

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
  (wall-clock time since the device was first tracked) is included.
  """

  use GenServer

  alias Octopus.Radar
  alias Octopus.Radar.SensorTransition

  @recovery_statuses [:reading, :initializing, :probing]

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

      # Load all persisted transitions up-front (one DB query) and replay them
      # per device before seeding from the current live status.
      history = SensorTransition.list_all_grouped()

      stats =
        Map.new(devices, fn d ->
          status = Radar.sensor_status(d.device_id)
          device_history = Map.get(history, d.device_id, [])
          {d.device_id, init_stats_for_device(status, device_history, now)}
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
    new_stat = apply_transition(current, status, now)

    if new_stat != current do
      SensorTransition.record(device_id, status, now)
    end

    {:noreply, Map.put(stats, device_id, new_stat)}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  ## Private helpers

  # Build initial stats for a device.
  #
  # If `history` is non-empty the accumulated DB transitions are replayed to
  # reconstruct lifetime counters.  The `since` cursor is then reset to `now`
  # so that the time gap introduced by the process restart is not attributed
  # to any status.  The last known status from the replay is kept as
  # `current_status`; the first PubSub event after subscribe will advance it
  # to the actual sensor state via `apply_transition` when they differ.
  #
  # When `history` is empty (first ever run) a clean state seeded from the
  # live sensor status is returned instead.
  defp init_stats_for_device(current_status, [], now) do
    new_sensor_stats(current_status, now)
  end

  defp init_stats_for_device(_current_status, [{first_status, first_ms} | rest], now) do
    base = new_sensor_stats(first_status, first_ms)

    replayed =
      Enum.reduce(rest, base, fn {status, occurred_at_ms}, acc ->
        apply_transition(acc, status, occurred_at_ms)
      end)

    # Reset the session cursor to now so the restart gap is invisible.
    %{replayed | since: now}
  end

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

    # Sum all per-status durations so that offline gaps (restarts, downtime) are
    # never counted.  `now - started_at` would include every period the process
    # was not running, making it a misleading denominator for ratios.
    total_online_ms = durations |> Map.values() |> Enum.sum()

    %{
      total_ms: total_online_ms,
      first_seen_at: stats.started_at,
      durations: durations,
      entries: stats.entries,
      dropouts: stats.dropouts,
      retries: stats.retries,
      current_status: stats.current_status
    }
  end
end
