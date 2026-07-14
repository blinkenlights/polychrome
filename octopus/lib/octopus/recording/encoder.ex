defmodule Octopus.Recording.Encoder do
  @moduledoc """
  Converts a `.octorec` panel recording (see `Octopus.Recording.Format`) into
  playable video using `ffmpeg`.

  Two kinds of output are produced:

    * **Per-panel videos** — one video per LED panel (`panel_00.mp4`, ...),
      each the native `panel_width x panel_height` resolution upscaled with
      nearest-neighbour so pixels stay crisp.
    * **A mixed video** (`mixed.mp4`) — all panels laid out side by side in
      panel order (the circular installation "unrolled" into a horizontal
      strip), i.e. width `num_panels * panel_width`, height `panel_height`.

  Recordings are event-timed (frames are written whenever the mixer emits one,
  not at a fixed rate), so records are resampled onto a constant frame rate
  using hold-last-frame semantics before encoding.

  The pixel/resampling helpers (`resample/2`, `panel_frame/3`, `strip_frame/2`)
  are pure and independently testable; only `encode/2` shells out to `ffmpeg`.
  """

  require Logger

  alias Octopus.Recording.Format

  @default_fps 30
  @default_scale 16

  @type geometry ::
          {num_panels :: pos_integer(), panel_width :: pos_integer(),
           panel_height :: pos_integer()}

  @doc """
  Encode `input_path` (a `.octorec` file) into videos.

  Options:

    * `:out` - output directory (default: sibling directory named after the
      recording file).
    * `:fps` - constant output frame rate (default `#{@default_fps}`).
    * `:scale` - integer upscale factor, nearest-neighbour (default `#{@default_scale}`).
    * `:panels` - emit per-panel videos (default `true`).
    * `:mixed` - emit the mixed strip video (default `true`).
    * `:ffmpeg` - ffmpeg executable (default `"ffmpeg"`).

  Returns `{:ok, [output_path]}` or `{:error, reason}`.
  """
  @spec encode(String.t(), keyword()) :: {:ok, [String.t()]} | {:error, term()}
  def encode(input_path, opts \\ []) do
    fps = Keyword.get(opts, :fps, @default_fps)
    scale = Keyword.get(opts, :scale, @default_scale)
    ffmpeg = Keyword.get(opts, :ffmpeg, "ffmpeg")
    do_panels? = Keyword.get(opts, :panels, true)
    do_mixed? = Keyword.get(opts, :mixed, true)
    out_dir = Keyword.get(opts, :out) || default_out_dir(input_path)

    with :ok <- ensure_ffmpeg(ffmpeg),
         {:ok, binary} <- read_recording(input_path),
         {:ok, header, records} <- Format.parse(binary),
         :ok <- ensure_records(records) do
      geom = {header.num_panels, header.panel_width, header.panel_height}
      frames = resample(records, fps)

      File.mkdir_p!(out_dir)
      raw_dir = Path.join(System.tmp_dir!(), "octorec-raw-#{System.unique_integer([:positive])}")
      File.mkdir_p!(raw_dir)

      try do
        outputs =
          []
          |> maybe_encode_panels(do_panels?, frames, geom, raw_dir, out_dir, fps, scale, ffmpeg)
          |> maybe_encode_mixed(do_mixed?, frames, geom, raw_dir, out_dir, fps, scale, ffmpeg)

        {:ok, Enum.reverse(outputs)}
      after
        File.rm_rf(raw_dir)
      end
    end
  end

  @doc "Whether the given ffmpeg executable is available on the system."
  @spec ffmpeg_available?(String.t()) :: boolean()
  def ffmpeg_available?(ffmpeg \\ "ffmpeg") do
    System.find_executable(ffmpeg) != nil
  end

  # Read a recording, transparently decompressing a .gz file.
  defp read_recording(path) do
    with {:ok, bin} <- File.read(path) do
      if String.ends_with?(path, ".gz") do
        try do
          {:ok, :zlib.gunzip(bin)}
        rescue
          error -> {:error, {:gunzip_failed, error}}
        end
      else
        {:ok, bin}
      end
    end
  end

  ## Pure pixel / timing helpers (testable without ffmpeg)

  @doc """
  Resample event-timed records onto a constant `fps`, holding the most recent
  frame for each output tick. Returns a list of frame pixel binaries.
  """
  @spec resample([{non_neg_integer(), binary()}], pos_integer()) :: [binary()]
  def resample([], _fps), do: []

  def resample(records, fps) when is_integer(fps) and fps > 0 do
    dt = max(div(1000, fps), 1)
    {last_offset, _} = List.last(records)

    times =
      if last_offset <= 0 do
        [0]
      else
        Enum.to_list(0..last_offset//dt)
      end

    {frames, _} =
      Enum.map_reduce(times, records, fn t, recs ->
        recs = advance(recs, t)
        {current(recs), recs}
      end)

    frames
  end

  # Advance to the last record whose offset is <= t (records are ascending).
  defp advance([{_o1, _d1}, {o2, _d2} = next | rest], t) when o2 <= t,
    do: advance([next | rest], t)

  defp advance(recs, _t), do: recs

  defp current([{_o, data} | _]), do: data

  @doc """
  Extract panel `panel_index`'s pixel block from a full frame. The result is a
  ready-to-use `panel_width x panel_height` RGB image (row-major).
  """
  @spec panel_frame(binary(), non_neg_integer(), geometry()) :: binary()
  def panel_frame(data, panel_index, {_n, pw, ph}) do
    block = pw * ph * 3
    binary_part(data, panel_index * block, block)
  end

  @doc """
  Build the mixed "strip" frame: all panels concatenated horizontally in panel
  order, producing a `(num_panels * panel_width) x panel_height` RGB image.
  """
  @spec strip_frame(binary(), geometry()) :: binary()
  def strip_frame(data, {n, pw, ph}) do
    row_bytes = pw * 3

    for y <- 0..(ph - 1), p <- 0..(n - 1), into: <<>> do
      offset = (p * ph + y) * pw * 3
      binary_part(data, offset, row_bytes)
    end
  end

  ## Encoding steps

  defp maybe_encode_panels(outputs, false, _frames, _geom, _raw, _out, _fps, _scale, _ffmpeg),
    do: outputs

  defp maybe_encode_panels(
         outputs,
         true,
         frames,
         {n, pw, ph} = geom,
         raw_dir,
         out_dir,
         fps,
         scale,
         ffmpeg
       ) do
    pad = n |> Kernel.-(1) |> max(1) |> Integer.to_string() |> String.length()

    Enum.reduce(0..(n - 1), outputs, fn p, acc ->
      raw = Path.join(raw_dir, "panel_#{p}.raw")
      write_raw(raw, frames, &panel_frame(&1, p, geom))

      out = Path.join(out_dir, "panel_#{String.pad_leading(Integer.to_string(p), pad, "0")}.mp4")
      :ok = run_ffmpeg(ffmpeg, raw, pw, ph, fps, scale, out)
      [out | acc]
    end)
  end

  defp maybe_encode_mixed(outputs, false, _frames, _geom, _raw, _out, _fps, _scale, _ffmpeg),
    do: outputs

  defp maybe_encode_mixed(
         outputs,
         true,
         frames,
         {n, pw, ph} = geom,
         raw_dir,
         out_dir,
         fps,
         scale,
         ffmpeg
       ) do
    raw = Path.join(raw_dir, "mixed.raw")
    write_raw(raw, frames, &strip_frame(&1, geom))

    out = Path.join(out_dir, "mixed.mp4")
    :ok = run_ffmpeg(ffmpeg, raw, n * pw, ph, fps, scale, out)
    [out | outputs]
  end

  defp write_raw(path, frames, transform) do
    File.open!(path, [:write, :raw, :binary], fn io ->
      Enum.each(frames, fn data -> IO.binwrite(io, transform.(data)) end)
    end)
  end

  defp run_ffmpeg(ffmpeg, raw, width, height, fps, scale, out) do
    args = [
      "-y",
      "-f",
      "rawvideo",
      "-pixel_format",
      "rgb24",
      "-video_size",
      "#{width}x#{height}",
      "-framerate",
      "#{fps}",
      "-i",
      raw,
      "-vf",
      "scale=iw*#{scale}:ih*#{scale}:flags=neighbor,pad=ceil(iw/2)*2:ceil(ih/2)*2",
      "-pix_fmt",
      "yuv420p",
      out
    ]

    case System.cmd(ffmpeg, args, stderr_to_stdout: true) do
      {_output, 0} ->
        :ok

      {output, code} ->
        Logger.error("[recording] ffmpeg failed (#{code}): #{output}")
        raise "ffmpeg failed with exit code #{code} for #{out}"
    end
  end

  ## Helpers

  defp ensure_ffmpeg(ffmpeg) do
    if ffmpeg_available?(ffmpeg) do
      :ok
    else
      {:error, :ffmpeg_not_found}
    end
  end

  defp ensure_records([]), do: {:error, :empty_recording}
  defp ensure_records(_records), do: :ok

  defp default_out_dir(input_path) do
    dir = Path.dirname(input_path)
    name = Path.basename(input_path, Path.extname(input_path))
    Path.join(dir, name)
  end
end
