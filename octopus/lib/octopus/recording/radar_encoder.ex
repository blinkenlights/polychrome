defmodule Octopus.Recording.RadarEncoder do
  @moduledoc """
  Renders a radar JSONL recording (`Octopus.Recording.RadarFormat`) into a
  top-down "scope" video.

  Each output frame is a top-down view of the installation's global frame: the
  origin (installation center) is the middle of the image, tracked targets are
  drawn as coloured dots (coloured per track id), with a boundary ring and
  centre marker for orientation. `+x` is right and `+y` is up.

  As with the panel encoder, the event-timed frames are resampled onto a
  constant frame rate. At each tick the scene is the union of the most recent
  frame from every sensor, so all sensors appear together on one scope.

  The scene/geometry helpers (`scope_frames/2`, `world_to_px/4`, `render/3`)
  are pure and independently testable; only `encode/2` shells out to `ffmpeg`.
  """

  require Logger

  alias Octopus.Recording.RadarFormat

  @default_fps 30
  @default_size 256
  @default_world_radius_m 8.0

  @bg {12, 12, 20}
  @ring {40, 60, 90}
  @center {90, 90, 110}
  @palette [
    {66, 135, 245},
    {245, 108, 66},
    {66, 245, 135},
    {245, 66, 197},
    {245, 224, 66},
    {66, 245, 245},
    {170, 110, 245},
    {245, 149, 66}
  ]

  @type track :: %{id: integer(), x: number(), y: number()}

  @doc """
  Encode `input_path` (a `.jsonl` radar recording) into a scope video.

  Options:

    * `:out` - output directory (default: sibling dir named after the file)
    * `:fps` - constant output frame rate (default #{@default_fps})
    * `:size` - square output size in pixels (default #{@default_size})
    * `:world_radius_m` - half-extent of the view in meters (default: from the
      recording metadata, else #{@default_world_radius_m})
    * `:name` - output filename (default `"radar.mp4"`)
    * `:ffmpeg` - ffmpeg executable (default `"ffmpeg"`)

  Returns `{:ok, [output_path]}` or `{:error, reason}`.
  """
  @spec encode(String.t(), keyword()) :: {:ok, [String.t()]} | {:error, term()}
  def encode(input_path, opts \\ []) do
    fps = Keyword.get(opts, :fps, @default_fps)
    size = Keyword.get(opts, :size, @default_size)
    ffmpeg = Keyword.get(opts, :ffmpeg, "ffmpeg")
    name = Keyword.get(opts, :name, "radar.mp4")
    out_dir = Keyword.get(opts, :out) || default_out_dir(input_path)

    with :ok <- ensure_ffmpeg(ffmpeg),
         {:ok, binary} <- File.read(input_path),
         {:ok, meta, frames} <- RadarFormat.parse(binary),
         :ok <- ensure_frames(frames) do
      world_radius_m =
        Keyword.get(opts, :world_radius_m) || meta["world_radius_m"] || @default_world_radius_m

      scenes = scope_frames(frames, fps)

      File.mkdir_p!(out_dir)

      raw_dir =
        Path.join(System.tmp_dir!(), "octorec-radar-#{System.unique_integer([:positive])}")

      File.mkdir_p!(raw_dir)

      try do
        raw = Path.join(raw_dir, "radar.raw")

        File.open!(raw, [:write, :raw, :binary], fn io ->
          Enum.each(scenes, fn {_t, tracks} ->
            IO.binwrite(io, render(tracks, world_radius_m, size))
          end)
        end)

        out = Path.join(out_dir, name)
        :ok = run_ffmpeg(ffmpeg, raw, size, fps, out)
        {:ok, [out]}
      after
        File.rm_rf(raw_dir)
      end
    end
  end

  @doc "Whether the given ffmpeg executable is available."
  @spec ffmpeg_available?(String.t()) :: boolean()
  def ffmpeg_available?(ffmpeg \\ "ffmpeg"), do: System.find_executable(ffmpeg) != nil

  ## Pure helpers

  @doc """
  Resample radar frames (from all sensors) onto a constant `fps`. Returns a
  list of `{offset_ms, tracks}` where `tracks` is the union of the most recent
  frame from each sensor at that tick.
  """
  @spec scope_frames([map()], pos_integer()) :: [{non_neg_integer(), [track()]}]
  def scope_frames([], _fps), do: []

  def scope_frames(frames, fps) when is_integer(fps) and fps > 0 do
    by_dev = Enum.group_by(frames, & &1.dev)
    last_t = frames |> Enum.map(& &1.t) |> Enum.max(fn -> 0 end)
    dt = max(div(1000, fps), 1)
    times = if last_t <= 0, do: [0], else: Enum.to_list(0..last_t//dt)

    init = Map.new(by_dev, fn {dev, fs} -> {dev, {fs, []}} end)

    {scenes, _} =
      Enum.map_reduce(times, init, fn t, dev_state ->
        dev_state =
          Map.new(dev_state, fn {dev, {remaining, current}} ->
            {dev, advance_dev(remaining, current, t)}
          end)

        tracks = dev_state |> Map.values() |> Enum.flat_map(fn {_rem, current} -> current end)
        {{t, tracks}, dev_state}
      end)

    scenes
  end

  defp advance_dev([%{t: ft, tracks: tr} | rest], _current, t) when ft <= t,
    do: advance_dev(rest, tr, t)

  defp advance_dev(remaining, current, _t), do: {remaining, current}

  @doc """
  Map a world position (meters) to pixel coordinates in a `size x size` image
  with the origin at the center, `+x` right and `+y` up. Clamped to bounds.
  """
  @spec world_to_px(number(), number(), number(), pos_integer()) ::
          {non_neg_integer(), non_neg_integer()}
  def world_to_px(x, y, world_radius_m, size) when world_radius_m > 0 do
    nx = clamp(x / world_radius_m, -1.0, 1.0)
    ny = clamp(y / world_radius_m, -1.0, 1.0)

    px = round((nx + 1.0) / 2.0 * (size - 1))
    py = round((1.0 - (ny + 1.0) / 2.0) * (size - 1))
    {px, py}
  end

  @doc """
  Render a single scope frame to a `size x size` RGB (rgb24) binary.
  """
  @spec render([track()], number(), pos_integer()) :: binary()
  def render(tracks, world_radius_m, size) do
    overrides =
      %{}
      |> draw_ring(size)
      |> draw_center(size)
      |> draw_tracks(tracks, world_radius_m, size)

    for y <- 0..(size - 1) do
      for x <- 0..(size - 1) do
        {r, g, b} = Map.get(overrides, {x, y}, @bg)
        <<r, g, b>>
      end
    end
    |> IO.iodata_to_binary()
  end

  ## Rendering internals

  defp draw_tracks(overrides, tracks, world_radius_m, size) do
    dot = max(div(size, 64), 2)

    Enum.reduce(tracks, overrides, fn track, acc ->
      {cx, cy} = world_to_px(track.x, track.y, world_radius_m, size)
      draw_disc(acc, cx, cy, dot, color_for(track.id), size)
    end)
  end

  defp draw_disc(acc, cx, cy, r, color, size) do
    for dy <- -r..r, dx <- -r..r, dx * dx + dy * dy <= r * r, reduce: acc do
      acc ->
        x = cx + dx
        y = cy + dy

        if x >= 0 and x < size and y >= 0 and y < size do
          Map.put(acc, {x, y}, color)
        else
          acc
        end
    end
  end

  defp draw_ring(acc, size) do
    cx = div(size, 2)
    cy = div(size, 2)
    rr = div(size, 2) - 2

    for deg <- 0..359, reduce: acc do
      acc ->
        rad = deg * :math.pi() / 180.0
        x = round(cx + rr * :math.cos(rad))
        y = round(cy + rr * :math.sin(rad))

        if x >= 0 and x < size and y >= 0 and y < size do
          Map.put(acc, {x, y}, @ring)
        else
          acc
        end
    end
  end

  defp draw_center(acc, size) do
    draw_disc(acc, div(size, 2), div(size, 2), 1, @center, size)
  end

  defp color_for(id) when is_integer(id), do: Enum.at(@palette, rem(id, length(@palette)))
  defp color_for(_id), do: hd(@palette)

  ## ffmpeg

  defp run_ffmpeg(ffmpeg, raw, size, fps, out) do
    args = [
      "-y",
      "-f",
      "rawvideo",
      "-pixel_format",
      "rgb24",
      "-video_size",
      "#{size}x#{size}",
      "-framerate",
      "#{fps}",
      "-i",
      raw,
      "-vf",
      "pad=ceil(iw/2)*2:ceil(ih/2)*2",
      "-pix_fmt",
      "yuv420p",
      out
    ]

    case System.cmd(ffmpeg, args, stderr_to_stdout: true) do
      {_output, 0} ->
        :ok

      {output, code} ->
        Logger.error("[recording] radar ffmpeg failed (#{code}): #{output}")
        raise "ffmpeg failed with exit code #{code} for #{out}"
    end
  end

  ## Helpers

  defp ensure_ffmpeg(ffmpeg) do
    if ffmpeg_available?(ffmpeg), do: :ok, else: {:error, :ffmpeg_not_found}
  end

  defp ensure_frames([]), do: {:error, :empty_recording}
  defp ensure_frames(_frames), do: :ok

  defp clamp(v, lo, hi), do: v |> max(lo) |> min(hi)

  defp default_out_dir(input_path) do
    dir = Path.dirname(input_path)
    name = Path.basename(input_path, Path.extname(input_path))
    Path.join(dir, name)
  end
end
