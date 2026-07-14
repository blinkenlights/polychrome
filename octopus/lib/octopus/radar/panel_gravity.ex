defmodule Octopus.Radar.PanelGravity do
  @moduledoc """
  Shared per-panel gravity factors derived from radar track proximity.

  Subscribes to radar frames, maintains a track registry, and ticks at a
  fixed rate to publish normalised gravity factors per installation panel
  (1-based indices). Consumers call `Octopus.Radar.panel_gravity/0` or
  subscribe via `Octopus.Radar.subscribe_panel_gravity/0`.
  """

  use GenServer

  require Logger

  alias Octopus.Radar.Frame
  alias Octopus.Radar.Mock.World
  alias Octopus.Radar.PanelGravity.{Core, Settings}
  alias Octopus.Radar.TrackMerge
  alias Phoenix.PubSub

  @topic_suffix "panel_gravity"
  @debug_log_interval_ms 1_000

  ## Client API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @spec topic() :: String.t()
  def topic, do: "#{Octopus.Radar.topic()}:#{@topic_suffix}"

  @doc "Return the latest gravity snapshot."
  @spec snapshot() :: map()
  def snapshot do
    GenServer.call(__MODULE__, :snapshot)
  end

  @doc false
  @spec tick() :: :ok
  def tick do
    GenServer.cast(__MODULE__, :tick)
  end

  ## GenServer callbacks

  @impl true
  def init(_opts) do
    num_panels = Octopus.Installation.num_panels()
    settings = Settings.get()
    panel_positions = Octopus.Installation.panel_world_gravity_positions_m()

    state = %{
      track_registry: %{},
      level: Core.empty_installation_panels(num_panels),
      ref: settings.min_ref,
      snapshot: empty_snapshot(num_panels, settings.min_ref),
      last_tick_ms: now_ms(),
      num_panels: num_panels,
      panel_positions: panel_positions,
      last_debug_ms: 0
    }

    {:ok, state, {:continue, :subscribe}}
  end

  @impl true
  def handle_continue(:subscribe, state) do
    :ok = Octopus.Radar.subscribe()
    schedule_tick(Settings.get().tick_hz)
    {:noreply, state}
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    {:reply, state.snapshot, state}
  end

  @impl true
  def handle_cast(:tick, state) do
    {:noreply, run_tick(state)}
  end

  @impl true
  def handle_info(:tick, state) do
    settings = Settings.get()
    schedule_tick(settings.tick_hz)
    {:noreply, run_tick(state)}
  end

  def handle_info({:radar_frame, device_id, %Frame{tracks: tracks}}, state) do
    now = now_ms()

    track_registry =
      Enum.reduce(tracks, state.track_registry, fn track, acc ->
        person = track_to_person(track, device_id)
        Map.put(acc, person.id, {person, now})
      end)

    {:noreply, %{state | track_registry: track_registry}}
  end

  def handle_info({:mock_world, _objects}, state), do: {:noreply, state}

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  ## Private helpers

  defp run_tick(state) do
    settings = Settings.get()
    now = now_ms()
    dt = (max(now - state.last_tick_ms, 1) / 1000.0) |> min(0.2)

    {people, source} = fetch_people(state.track_registry, now, settings)

    raw =
      people
      |> Core.raw_gravity(state.panel_positions, settings)
      |> ensure_all_panels(state.num_panels)

    ref = Core.update_ref(state.ref, raw, settings.adaptive, dt, settings)
    target = Core.targets(raw, ref, settings)

    level =
      state.level
      |> Core.smooth_asymmetric(target, dt, settings)
      |> Enum.map(fn {panel, value} -> {panel, clamp01(value)} end)
      |> Map.new()

    snapshot = %{
      gravity: level,
      raw: raw,
      ref: ref,
      at: now
    }

    state =
      if debug_due?(now, state.last_debug_ms, people) do
        log_debug(source, people, raw, target, level, dt, ref)
        %{state | last_debug_ms: now}
      else
        state
      end

    if changed_enough?(state.snapshot, snapshot, settings.broadcast_epsilon) do
      :ok = PubSub.broadcast(Octopus.PubSub, topic(), {:panel_gravity, snapshot})
    end

    %{state | level: level, ref: ref, snapshot: snapshot, last_tick_ms: now}
  end

  defp fetch_people(track_registry, now, %Settings{} = settings) do
    people =
      track_registry
      |> active_people(now, settings.track_stale_ms)
      |> TrackMerge.merge(settings.merge_radius_m)

    cond do
      people != [] ->
        {people, :tracks}

      map_size(track_registry) > 0 ->
        {[], :stale}

      true ->
        {mock_world_people(), :mock_world}
    end
  end

  defp mock_world_people do
    case Process.whereis(World) do
      nil ->
        []

      _pid ->
        World.objects()
        |> Enum.map(&object_to_person/1)
    end
  rescue
    _ -> []
  end

  defp active_people(track_registry, now, stale_ms) do
    track_registry
    |> Enum.filter(fn {_id, {_person, seen_at}} -> now - seen_at <= stale_ms end)
    |> Enum.map(fn {_id, {person, _seen_at}} -> person end)
  end

  defp changed_enough?(old_snapshot, new_snapshot, epsilon) do
    old = Map.fetch!(old_snapshot, :gravity)
    new = Map.fetch!(new_snapshot, :gravity)

    Enum.any?(old, fn {panel, value} ->
      abs(value - Map.get(new, panel, 0.0)) > epsilon
    end) or
      Enum.any?(new, fn {panel, value} ->
        abs(value - Map.get(old, panel, 0.0)) > epsilon
      end)
  end

  defp ensure_all_panels(map, num_panels) do
    Enum.reduce(1..num_panels, map, fn panel, acc ->
      Map.put_new(acc, panel, 0.0)
    end)
  end

  defp track_to_person(track, device_id) do
    %{
      id: device_id * 10_000 + track.id,
      x: track.x,
      y: track.y,
      vx: track.vx,
      vy: track.vy
    }
  end

  defp object_to_person(obj) do
    %{
      id: Map.get(obj, :id),
      x: Map.get(obj, :x, 0.0),
      y: Map.get(obj, :y, 0.0),
      vx: Map.get(obj, :vx, 0.0),
      vy: Map.get(obj, :vy, 0.0)
    }
  end

  defp empty_snapshot(num_panels, ref) do
    %{
      gravity: Core.empty_installation_panels(num_panels),
      raw: Core.empty_installation_panels(num_panels),
      ref: ref,
      at: 0
    }
  end

  defp schedule_tick(hz) when is_integer(hz) and hz > 0 do
    interval = max(trunc(1000 / hz), 1)
    Process.send_after(self(), :tick, interval)
  end

  defp debug_due?(_now, _last_debug_ms, []), do: false

  defp debug_due?(now, last_debug_ms, _people) do
    now - last_debug_ms >= @debug_log_interval_ms
  end

  defp log_debug(source, people, raw, target, level, dt, ref) do
    raw_span = map_span(raw)
    {peak_panel, peak_level} = peak_entry(level)

    Logger.debug(
      "[PanelGravity] source=#{source} people=#{format_people(people)} " <>
        "dt=#{Float.round(dt, 3)}s ref=#{Float.round(ref, 4)} raw_span=#{Float.round(raw_span, 4)} " <>
        "peak=p#{peak_panel} raw=#{fmt(raw, peak_panel)} tgt=#{fmt(target, peak_panel)} " <>
        "lvl=#{Float.round(peak_level, 3)} top_raw=[#{top_panels(raw)}] " <>
        "top_lvl=[#{top_panels(level)}]"
    )
  end

  defp format_people(people) do
    people
    |> Enum.map(fn %{x: x, y: y} -> "(#{Float.round(x, 2)},#{Float.round(y, 2)})" end)
    |> Enum.join(" ")
  end

  defp top_panels(map, n \\ 3) do
    map
    |> Enum.sort_by(fn {_panel, value} -> -value end)
    |> Enum.take(n)
    |> Enum.map(fn {panel, value} -> "p#{panel}=#{Float.round(value, 3)}" end)
    |> Enum.join(" ")
  end

  defp peak_entry(map) do
    Enum.max_by(map, fn {_panel, value} -> value end, fn -> {0, 0.0} end)
  end

  defp fmt(map, panel), do: Float.round(Map.get(map, panel, 0.0), 3)

  defp map_span(map) do
    values = Map.values(map)
    Enum.max(values, fn -> 0.0 end) - Enum.min(values, fn -> 0.0 end)
  end

  defp now_ms, do: :erlang.monotonic_time(:millisecond)
  defp clamp01(v), do: v |> max(0.0) |> min(1.0)
end
