defmodule Octopus.Recording.RadarFormat do
  @moduledoc """
  Line-delimited JSON (JSONL) container for radar recordings.

  Radar data is low-volume and variable length (a frame carries a variable
  number of tracks), so a text/JSONL format is used instead of the fixed-size
  binary format used for panels. The first line is a metadata object; every
  subsequent line is one radar frame.

  Timestamps use the same convention as the panel recording so the two can be
  aligned on a shared timeline: `t` is milliseconds since the recording's
  monotonic start, and the metadata line carries the wall-clock `started_at_ms`.

  Track positions/velocities are in the **installation global frame** (meters
  and meters/second), i.e. after `Octopus.Radar.Transform` has mapped each
  sensor's local readings into the shared, center-origin coordinate system.

  ## Metadata line

      {"v": 1, "started_at_ms": 1700000000000, "world_radius_m": 8.0}

  ## Frame line

      {"t": 123, "dev": 1, "n": 42,
       "tracks": [{"id": 7, "x": 1.2, "y": -0.5, "z": 2.0,
                   "vx": 0.1, "vy": 0.0, "vz": 0.0}]}
  """

  alias Octopus.Radar.Track

  @version 1

  @doc "Current radar format version."
  @spec version() :: pos_integer()
  def version, do: @version

  @doc "Encode the metadata line (including the trailing newline)."
  @spec meta_line(non_neg_integer(), number()) :: binary()
  def meta_line(started_at_ms, world_radius_m) do
    line(%{
      "v" => @version,
      "started_at_ms" => started_at_ms,
      "world_radius_m" => world_radius_m
    })
  end

  @doc "Encode one radar frame line (including the trailing newline)."
  @spec frame_line(non_neg_integer(), pos_integer(), non_neg_integer(), [Track.t()]) :: binary()
  def frame_line(offset_ms, device_id, frame_number, tracks) do
    line(%{
      "t" => offset_ms,
      "dev" => device_id,
      "n" => frame_number,
      "tracks" => Enum.map(tracks, &track_map/1)
    })
  end

  @doc """
  Parse a full JSONL recording into `{:ok, meta, frames}`.

  `frames` is a list of maps with atom keys `:t`, `:dev`, `:n`, and `:tracks`
  (each track a map with atom keys `:id`, `:x`, `:y`, `:z`, `:vx`, `:vy`,
  `:vz`). Blank lines are ignored.
  """
  @spec parse(binary()) :: {:ok, map(), [map()]} | {:error, term()}
  def parse(binary) when is_binary(binary) do
    lines =
      binary
      |> String.split("\n", trim: true)

    case lines do
      [] ->
        {:error, :empty_recording}

      [meta_line | frame_lines] ->
        meta = JSON.decode!(meta_line)
        frames = Enum.map(frame_lines, &decode_frame/1)
        {:ok, meta, frames}
    end
  rescue
    error -> {:error, error}
  end

  defp decode_frame(line) do
    raw = JSON.decode!(line)

    %{
      t: raw["t"],
      dev: raw["dev"],
      n: raw["n"],
      tracks: Enum.map(raw["tracks"] || [], &decode_track/1)
    }
  end

  defp decode_track(t) do
    %{
      id: t["id"],
      x: t["x"],
      y: t["y"],
      z: t["z"],
      vx: t["vx"],
      vy: t["vy"],
      vz: t["vz"]
    }
  end

  defp track_map(%Track{} = track) do
    %{
      "id" => track.id,
      "x" => track.x,
      "y" => track.y,
      "z" => track.z,
      "vx" => track.vx,
      "vy" => track.vy,
      "vz" => track.vz
    }
  end

  defp line(map), do: JSON.encode!(map) <> "\n"
end
