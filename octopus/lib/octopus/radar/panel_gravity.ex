defmodule Octopus.Radar.PanelGravity do
  @moduledoc """
  Shared per-panel gravity factors derived from radar / mock-world people.

  Inputs (radar frames, mock world, settings) only update state and request a
  flush. A flush recomputes at most once per `@flush_interval_ms`
  (`objects × panels` distance evaluations), so bursty sensor input is
  coalesced. Cross-sensor duplicates are folded into one "combined object" via
  `Octopus.Radar.fuse_people/1` before gravity sees them, so an object
  drifting in/out of a second sensor's field of view doesn't change the
  contributing object count underneath it.

  Panel levels are smoothed with a symmetric first-order lag (`Core.smooth/4`)
  controlled by `easing_tau` (default 1.5 s). Both rising (object appears) and
  falling (object departs) transitions happen at the same rate, which eliminates
  flashing from brief transient positions while giving a smooth "glow follows
  you" effect for moving objects. A flush always recomputes even when the input
  fingerprint is unchanged so the easing tail keeps decaying on the stale-check
  heartbeat while idle.
  Consumers subscribe via `Octopus.Radar.subscribe_panel_gravity/0` or read
  `snapshot/0`.
  """

  use GenServer

  alias Octopus.Radar.Frame
  alias Octopus.Radar.Mock.World
  alias Octopus.Radar.PanelGravity.{Core, Settings}
  alias Phoenix.PubSub

  @topic_suffix "panel_gravity"
  @debug_log_interval_ms 1_000
  # Low-rate tick only for stale-track expiry (not for continuous recomputes).
  @stale_check_ms 250
  # Tracks whose XY speed is below this threshold (m/s) are treated as
  # stationary and excluded from gravity computation.
  @velocity_min_m_s 0.05
  # Coalesce bursty inputs (6 sensors × 10 Hz + mock world) into at most one
  # recompute/broadcast per interval. No timer runs while nothing is dirty.
  @flush_interval_ms 33

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
    GenServer.cast(__MODULE__, :recompute)
  end

  ## GenServer callbacks

  @impl true
  def init(_opts) do
    num_panels = Octopus.Installation.num_panels()
    north = Octopus.Radar.north_panel()

    state = %{
      track_registry: %{},
      mock_people: [],
      level: Core.empty_installation_panels(num_panels),
      snapshot: empty_snapshot(num_panels),
      num_panels: num_panels,
      north_panel: north,
      panel_positions: gravity_panel_positions(north),
      input_fp: nil,
      dirty: false,
      dirty_source: :boot,
      flush_scheduled: false,
      # Seed relative to monotonic now (which can be negative at VM start) so the
      # very first flush runs immediately instead of being deferred.
      last_flush_ms: now_ms() - @flush_interval_ms,
      last_level_ms: now_ms(),
      last_debug_ms: nil,
      frames_seen: 0,
      last_frame_tracks: 0
    }

    {:ok, state, {:continue, :subscribe}}
  end

  @impl true
  def handle_continue(:subscribe, state) do
    :ok = Octopus.Radar.subscribe()

    if Process.whereis(World) do
      :ok = PubSub.subscribe(Octopus.PubSub, World.world_topic())
    end

    schedule_stale_check()
    {:noreply, state |> mark_dirty(:boot) |> request_flush()}
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    {:reply, state.snapshot, state}
  end

  @impl true
  def handle_cast(:recompute, state) do
    {:noreply, state |> mark_dirty(:cast) |> request_flush()}
  end

  @impl true
  def handle_info(:stale_check, state) do
    schedule_stale_check()
    {:noreply, state |> mark_dirty(:stale_check) |> request_flush()}
  end

  def handle_info(:flush, state) do
    state = %{state | flush_scheduled: false}
    state = if state.dirty, do: do_flush(state), else: state
    {:noreply, state}
  end

  def handle_info({:radar_frame, device_id, %Frame{tracks: tracks}}, state) do
    now = now_ms()

    track_registry =
      Enum.reduce(tracks, state.track_registry, fn track, acc ->
        person = track_to_person(track, device_id)

        Map.put(acc, person.id, {person, now})
      end)

    state = %{
      state
      | track_registry: track_registry,
        frames_seen: state.frames_seen + 1,
        last_frame_tracks: length(tracks)
    }

    {:noreply, state |> mark_dirty(:tracks) |> request_flush()}
  end

  def handle_info({:mock_world, objects}, state) when is_list(objects) do
    people = Enum.map(objects, &object_to_person/1)
    {:noreply, %{state | mock_people: people} |> mark_dirty(:mock_world) |> request_flush()}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  ## Private helpers

  defp mark_dirty(state, source) do
    %{state | dirty: true, dirty_source: source}
  end

  # Recompute immediately when the interval has elapsed, otherwise defer with a
  # single timer that coalesces every dirty input until it fires.
  defp request_flush(%{flush_scheduled: true} = state), do: state

  defp request_flush(state) do
    elapsed = now_ms() - state.last_flush_ms

    if elapsed >= @flush_interval_ms do
      do_flush(state)
    else
      Process.send_after(self(), :flush, @flush_interval_ms - elapsed)
      %{state | flush_scheduled: true}
    end
  end

  defp do_flush(state) do
    settings = Settings.get()
    north = Octopus.Radar.north_panel()

    state =
      if north != state.north_panel do
        %{
          state
          | north_panel: north,
            panel_positions: gravity_panel_positions(north)
        }
      else
        state
      end

    {people, people_source} = fetch_people(state, settings)
    fp = input_fingerprint(people, settings, north)
    state = %{state | dirty: false, last_flush_ms: now_ms()}

    # Always recompute (even when the fingerprint is unchanged): the release
    # envelope keeps decaying toward target on every heartbeat while a
    # departed object's gravity is still fading out.
    state = recompute(state, people, people_source, settings, fp, state.dirty_source)

    # If levels are still moving toward their target (easing tail), keep
    # scheduling flushes at the render rate so the decay is smooth — without
    # this the easing continues only at the @stale_check_ms rate (250 ms)
    # which produces visible steps.
    if still_settling?(state, settings.broadcast_epsilon) do
      request_flush(mark_dirty(state, :settling))
    else
      state
    end
  end

  defp recompute(state, people, people_source, settings, fp, source) do
    now = now_ms()
    dt = ((now - state.last_level_ms) |> max(1)) / 1000.0 |> min(1.0)

    max_g  = clamp01(settings.max_gravity_pct / 100.0)

    # Linear nearest-object gravity: values are already in 0..1, no normalisation needed.
    raw =
      people
      |> Core.raw_gravity(
           state.panel_positions,
           settings.near_dist_m * 1.0,
           settings.far_dist_m * 1.0,
           0.0,
           max_g
         )
      |> ensure_all_panels(state.num_panels)

    target = raw
    level = Core.smooth(state.level, target, dt, settings)

    snapshot = %{
      gravity: level,
      target: target,
      raw: raw,
      at: now
    }

    state =
      if debug_due?(now, state.last_debug_ms) do
        log_debug(people_source, people, raw, target, level, settings, state, source)
        %{state | last_debug_ms: now}
      else
        state
      end

    if changed_enough?(state.snapshot, snapshot, settings.broadcast_epsilon) do
      :ok = PubSub.broadcast(Octopus.PubSub, topic(), {:panel_gravity, snapshot})
    end

    %{state | level: level, snapshot: snapshot, input_fp: fp, last_level_ms: now}
  end

  defp fetch_people(state, %Settings{} = settings) do
    now = now_ms()

    raw_people = active_people(state.track_registry, now, settings.track_stale_ms)

    people =
      if settings.fuse_people do
        Octopus.Radar.fuse_people(raw_people)
      else
        raw_people
      end

    cond do
      people != [] ->
        {people, :tracks}

      map_size(state.track_registry) > 0 ->
        {[], :stale}

      true ->
        {state.mock_people, :mock_world}
    end
  end

  defp input_fingerprint(people, settings, north_panel) do
    people_key =
      people
      |> Enum.map(fn p ->
        {Map.get(p, :id),
         Float.round(p.x, 3), Float.round(p.y, 3),
         Float.round(Map.get(p, :vx, 0.0), 2),
         Float.round(Map.get(p, :vy, 0.0), 2)}
      end)
      |> Enum.sort()

    settings_key = {settings.easing_tau, settings.near_dist_m, settings.far_dist_m, settings.fuse_people}

    {people_key, settings_key, north_panel}
  end

  defp active_people(track_registry, now, stale_ms) do
    clutter_filter? = Octopus.Radar.clutter_filter_enabled?()

    track_registry
    |> Enum.filter(fn {id, {person, seen_at}} ->
      in_time? = now - seen_at <= stale_ms

      clutter_ok? =
        if clutter_filter? do
          device_id = div(id, 10_000)
          track_id = rem(id, 10_000)
          Octopus.Radar.clutter_filter_track_qualified?(device_id, track_id)
        else
          true
        end

      moving? = :math.sqrt(person.vx * person.vx + person.vy * person.vy) >= @velocity_min_m_s

      in_time? and clutter_ok? and moving?
    end)
    |> Enum.map(fn {_id, {person, _seen_at}} -> person end)
  end

  defp clamp01(v), do: v |> max(0.0) |> min(1.0)

  defp changed_enough?(old_snapshot, new_snapshot, epsilon) do
    map_changed?(Map.fetch!(old_snapshot, :gravity), Map.fetch!(new_snapshot, :gravity), epsilon) or
      map_changed?(
        Map.get(old_snapshot, :target, %{}),
        Map.get(new_snapshot, :target, %{}),
        epsilon
      )
  end

  defp map_changed?(old, new, epsilon) do
    Enum.any?(old, fn {panel, value} ->
      abs(value - Map.get(new, panel, 0.0)) > epsilon
    end) or
      Enum.any?(new, fn {panel, value} ->
        abs(value - Map.get(old, panel, 0.0)) > epsilon
      end)
  end

  defp still_settling?(state, epsilon) do
    target = Map.get(state.snapshot, :target, %{})

    Enum.any?(state.level, fn {panel, val} ->
      abs(val - Map.get(target, panel, 0.0)) > epsilon
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

  defp gravity_panel_positions(north_panel) do
    Octopus.Installation.panel_positions_m(
      reference: :inner_face,
      north_panel: north_panel
    )
    |> Enum.map(&Map.take(&1, [:panel, :x, :y]))
  end

  defp empty_snapshot(num_panels) do
    empty = Core.empty_installation_panels(num_panels)
    %{gravity: empty, target: empty, raw: empty, at: 0}
  end

  defp schedule_stale_check do
    Process.send_after(self(), :stale_check, @stale_check_ms)
  end

  defp debug_due?(_now, nil), do: true

  defp debug_due?(now, last_debug_ms) when is_integer(last_debug_ms) do
    last_debug_ms == 0 or now - last_debug_ms >= @debug_log_interval_ms
  end

  defp log_debug(people_source, people, raw, target, level, settings, state, trigger) do
    {peak_panel, peak_level} = peak_entry(level)
    raw_values = Map.values(raw)
    raw_max = Enum.max(raw_values, fn -> 0.0 end)

      _ = {trigger, people_source, people, state, settings, raw_max, peak_panel, peak_level, target}
  end


  defp peak_entry(map) do
    Enum.max_by(map, fn {_panel, value} -> value end, fn -> {0, 0.0} end)
  end

  defp now_ms, do: :erlang.monotonic_time(:millisecond)
end
