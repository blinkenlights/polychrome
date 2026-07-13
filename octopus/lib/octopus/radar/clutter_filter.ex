defmodule Octopus.Radar.ClutterFilter do
  @moduledoc false
  use Agent

  alias Octopus.Radar.{Frame, Track, ViewSettings}

  # Qualification counts frame time while the track is considered "moving".
  # Speed comes from the device-reported velocity; displacement catches slow
  # drift when velocity is near zero but position still changes noticeably.
  @min_speed_m_s 0.08
  @displacement_threshold_m 0.05
  @registry_stale_ms 300_000
  @qualification_ms 3_000
  @history_window_ms 10_000

  def start_link(_opts) do
    Agent.start_link(fn -> %{registry: %{}} end, name: __MODULE__)
  end

  @spec reset() :: :ok
  def reset do
    if Process.whereis(__MODULE__) do
      Agent.update(__MODULE__, fn _ -> %{registry: %{}} end)
    end

    :ok
  end

  @spec filter_frame(pos_integer(), Frame.t()) :: Frame.t()
  def filter_frame(_device_id, %Frame{tracks: []} = frame), do: frame

  def filter_frame(device_id, %Frame{} = frame) do
    if Process.whereis(__MODULE__) do
      Agent.get_and_update(__MODULE__, fn state ->
        {filtered, new_state} = do_filter(device_id, frame, state)
        {filtered, new_state}
      end)
    else
      frame
    end
  end

  @spec track_qualified?(pos_integer(), non_neg_integer()) :: boolean()
  def track_qualified?(device_id, track_id) do
    if Process.whereis(__MODULE__) do
      Agent.get(__MODULE__, fn %{registry: registry} ->
        case Map.get(registry, {device_id, track_id}) do
          nil -> false
          entry -> entry.qualified
        end
      end)
    else
      true
    end
  end

  @spec track_debug(pos_integer(), non_neg_integer()) :: map() | nil
  def track_debug(device_id, track_id) do
    if Process.whereis(__MODULE__) do
      now = System.monotonic_time(:millisecond)

      Agent.get(__MODULE__, fn %{registry: registry} ->
        case Map.get(registry, {device_id, track_id}) do
          nil -> nil
          entry -> format_track_debug(device_id, track_id, entry, now)
        end
      end)
    end
  end

  defp do_filter(device_id, %Frame{received_at: frame_ts} = frame, %{registry: registry}) do
    now = frame_ts
    enabled = clutter_filter_enabled?()

    {registry, tracks} =
      Enum.reduce(frame.tracks, {registry, []}, fn %Track{} = track, {reg, acc} ->
        key = {device_id, track.id}
        entry = update_entry(Map.get(reg, key), track, now)
        reg = Map.put(reg, key, entry)

        if enabled and not entry.qualified do
          {reg, acc}
        else
          {reg, [track | acc]}
        end
      end)

    registry = prune_registry(registry, now)
    {%Frame{frame | tracks: Enum.reverse(tracks)}, %{registry: registry}}
  end

  defp clutter_filter_enabled? do
    if Process.whereis(ViewSettings), do: ViewSettings.clutter_filter(), else: true
  end

  defp update_entry(nil, %Track{} = track, now) do
    entry = %{
      x: track.x,
      y: track.y,
      z: track.z,
      first_seen: now,
      moving_ms: 0,
      qualified: false,
      last_seen: now,
      history: []
    }

    append_history_sample(entry, nil, track, now)
  end

  defp update_entry(prev, %Track{} = track, now) do
    delta = now - prev.last_seen

    moving_ms =
      if track_moving?(prev, track) do
        prev.moving_ms + delta
      else
        prev.moving_ms
      end

    qualified = prev.qualified or moving_ms >= qualification_ms()

    entry = %{
      x: track.x,
      y: track.y,
      z: track.z,
      first_seen: prev.first_seen,
      moving_ms: moving_ms,
      qualified: qualified,
      last_seen: now,
      history: prev.history
    }

    append_history_sample(entry, prev, track, now)
  end

  defp append_history_sample(entry, prev, %Track{} = track, now) do
    displacement =
      if prev do
        frame_displacement(prev, track)
      else
        0.0
      end

    moving = prev != nil and track_moving?(prev, track)

    sample = %{
      ts: now,
      x: track.x,
      y: track.y,
      z: track.z,
      vx: track.vx,
      vy: track.vy,
      vz: track.vz,
      speed: track_speed(track),
      displacement: displacement,
      moving: moving,
      moving_ms: entry.moving_ms,
      qualified: entry.qualified
    }

    history =
      entry.history
      |> List.insert_at(0, sample)
      |> trim_history(now)

    %{entry | history: history}
  end

  defp trim_history(history, now) do
    cutoff = now - history_window_ms()

    Enum.filter(history, fn sample -> sample.ts >= cutoff end)
  end

  defp format_track_debug(device_id, track_id, entry, now) do
    %{
      "captured_at" => DateTime.to_iso8601(DateTime.utc_now()),
      "track" => %{
        "device_id" => device_id,
        "track_id" => track_id,
        "label" => track_label(device_id, track_id),
        "first_seen_ms_ago" => now - entry.first_seen,
        "last_seen_ms_ago" => now - entry.last_seen
      },
      "filter" => %{
        "clutter_filter_enabled" => clutter_filter_enabled?(),
        "qualified" => entry.qualified,
        "moving_ms" => entry.moving_ms,
        "qualification_ms" => qualification_ms(),
        "min_speed_m_s" => @min_speed_m_s,
        "displacement_threshold_m" => @displacement_threshold_m,
        "history_window_ms" => history_window_ms()
      },
      "history" => Enum.map(entry.history, &history_sample_to_json(&1, now))
    }
  end

  defp history_sample_to_json(sample, now) do
    %{
      "ms_ago" => now - sample.ts,
      "global" => coords_map(sample.x, sample.y, sample.z),
      "velocity" => coords_map(sample.vx, sample.vy, sample.vz),
      "speed_m_s" => round_float(sample.speed),
      "displacement_m" => round_float(sample.displacement),
      "moving" => sample.moving,
      "moving_ms" => sample.moving_ms,
      "qualified" => sample.qualified
    }
  end

  defp track_label(device_id, track_id) do
    letter = <<?A + rem(device_id - 1, 26)>>
    "#{letter}#{track_id}"
  end

  defp coords_map(x, y, z) do
    %{"x_m" => round_float(x), "y_m" => round_float(y), "z_m" => round_float(z)}
  end

  defp round_float(v) when is_float(v), do: Float.round(v, 4)
  defp round_float(v) when is_integer(v), do: v * 1.0

  defp track_moving?(prev, %Track{} = track) do
    track_speed(track) > @min_speed_m_s or
      frame_displacement(prev, track) > @displacement_threshold_m
  end

  defp track_speed(%Track{vx: vx, vy: vy, vz: vz}) do
    :math.sqrt(vx * vx + vy * vy + vz * vz)
  end

  defp frame_displacement(prev, %Track{} = track) do
    dx = track.x - prev.x
    dy = track.y - prev.y
    dz = track.z - prev.z

    :math.sqrt(dx * dx + dy * dy + dz * dz)
  end

  defp prune_registry(registry, now) do
    Map.filter(registry, fn {_key, entry} ->
      now - entry.last_seen < @registry_stale_ms
    end)
  end

  defp qualification_ms do
    Application.get_env(:octopus, __MODULE__, [])
    |> Keyword.get(:qualification_ms, @qualification_ms)
  end

  defp history_window_ms do
    Application.get_env(:octopus, __MODULE__, [])
    |> Keyword.get(:history_window_ms, @history_window_ms)
  end
end
