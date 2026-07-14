defmodule Octopus.Radar.PanelActivity do
  @moduledoc """
  Shared per-panel activity factors derived from radar tracks.

  Subscribes to radar frames, maintains a track registry, and ticks at a
  fixed rate to publish normalised activity factors per installation panel
  (1-based indices). Consumers call `Octopus.Radar.panel_activity/0` or
  subscribe via `Octopus.Radar.subscribe_panel_activity/0`.
  """

  use GenServer

  alias Octopus.Radar.Frame
  alias Octopus.Radar.Mock.World
  alias Octopus.Radar.PanelActivity.{Core, Settings}
  alias Octopus.Radar.PanelMapping
  alias Phoenix.PubSub

  @topic_suffix "panel_activity"

  ## Client API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @spec topic() :: String.t()
  def topic, do: "#{Octopus.Radar.topic()}:#{@topic_suffix}"

  @doc "Return the latest activity snapshot."
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

    state = %{
      track_registry: %{},
      level: Core.empty_installation_panels(num_panels),
      ref: settings.min_ref,
      snapshot: empty_snapshot(num_panels, settings.min_ref),
      last_tick_ms: now_ms(),
      num_panels: num_panels
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
    num_panels = state.num_panels
    north_panel = Octopus.Radar.north_panel()
    ring_outer = PanelMapping.ring_radius()

    people = fetch_people(state.track_registry, now, settings.track_stale_ms)

    raw_frame = Core.raw_factors(people, num_panels, ring_outer, settings)
    ref = Core.update_ref(state.ref, raw_frame, settings.adaptive, dt, settings)
    target_frame = Core.targets(raw_frame, ref, settings)

    level_frame =
      state.level
      |> frame_panel_level(num_panels)
      |> Core.smooth_asymmetric(target_frame, dt, settings)

    level =
      level_frame
      |> Core.to_installation_panels(num_panels, north_panel)
      |> Enum.map(fn {panel, value} -> {panel, clamp01(value)} end)
      |> Map.new()

    raw = Core.to_installation_panels(raw_frame, num_panels, north_panel)

    snapshot = %{
      factors: level,
      raw: raw,
      ref: ref,
      at: now
    }

    :ok = PubSub.broadcast(Octopus.PubSub, topic(), {:panel_activity, snapshot})

    %{state | level: level, ref: ref, snapshot: snapshot, last_tick_ms: now}
  end

  defp fetch_people(track_registry, now, stale_ms) do
    people = active_people(track_registry, now, stale_ms)

    cond do
      people != [] ->
        people

      map_size(track_registry) > 0 ->
        []

      true ->
        mock_world_people()
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

  defp frame_panel_level(level, num_panels) do
    north_panel = Octopus.Radar.north_panel()

    for frame_panel <- 0..(num_panels - 1), into: %{} do
      install_panel =
        PanelMapping.installation_panel_of_frame(frame_panel, num_panels, north_panel)

      {frame_panel, Map.get(level, install_panel, 0.0)}
    end
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
      factors: Core.empty_installation_panels(num_panels),
      raw: Core.empty_installation_panels(num_panels),
      ref: ref,
      at: 0
    }
  end

  defp schedule_tick(hz) when is_integer(hz) and hz > 0 do
    interval = max(trunc(1000 / hz), 1)
    Process.send_after(self(), :tick, interval)
  end

  defp now_ms, do: :erlang.monotonic_time(:millisecond)
  defp clamp01(v), do: v |> max(0.0) |> min(1.0)
end
