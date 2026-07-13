defmodule Octopus.Radar.ClutterFilter do
  @moduledoc false
  use Agent

  alias Octopus.Radar.{Frame, Track, ViewSettings}

  # Movement below this threshold (meters, 3D) is treated as radar jitter, not
  # real motion. Tracks must accumulate `@qualification_ms` of time spent moving
  # beyond this threshold before they are forwarded to consumers.
  @position_threshold_m 0.20
  @registry_stale_ms 300_000
  @qualification_ms 3_000

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

  defp do_filter(device_id, %Frame{} = frame, %{registry: registry}) do
    now = System.monotonic_time(:millisecond)
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
    %{
      x: track.x,
      y: track.y,
      z: track.z,
      first_seen: now,
      moving_ms: 0,
      qualified: false,
      last_seen: now
    }
  end

  defp update_entry(prev, %Track{} = track, now) do
    moved = position_moved?(prev, track)
    delta = now - prev.last_seen

    moving_ms =
      if moved do
        prev.moving_ms + delta
      else
        prev.moving_ms
      end

    qualified = prev.qualified or moving_ms >= qualification_ms()

    %{
      x: track.x,
      y: track.y,
      z: track.z,
      first_seen: prev.first_seen,
      moving_ms: moving_ms,
      qualified: qualified,
      last_seen: now
    }
  end

  defp position_moved?(prev, %Track{} = track) do
    dx = track.x - prev.x
    dy = track.y - prev.y
    dz = track.z - prev.z

    :math.sqrt(dx * dx + dy * dy + dz * dz) > @position_threshold_m
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
end
