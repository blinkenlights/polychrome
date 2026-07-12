defmodule Mix.Tasks.Octopus.Recording.Encode do
  @shortdoc "Encode a .octorec panel recording into per-panel and mixed videos"

  @moduledoc """
  Convert a recording produced by `Octopus.Recording` into video.

      mix octopus.recording.encode PATH [options]

  `PATH` may be:

    * a `.octorec` panel recording -> per-panel videos + a mixed video
    * a `.jsonl` radar recording -> a top-down radar scope video
    * a session directory (containing `panels.octorec` and/or `radar.jsonl`)
      -> both of the above, encoded into that directory

  For panel recordings this writes one video per panel plus a single mixed
  video (all panels laid out side by side).

  ## Options

    * `--out DIR` - output directory (default: sibling dir named after the file)
    * `--fps N` - constant output frame rate (default: 30)
    * `--scale N` - integer nearest-neighbour upscale factor (default: 16)
    * `--no-panels` - skip per-panel videos
    * `--no-mixed` - skip the mixed video
    * `--ffmpeg PATH` - ffmpeg executable to use (default: "ffmpeg")

  ## Examples

      mix octopus.recording.encode recordings/panels-20260712-143000.octorec
      mix octopus.recording.encode rec.octorec --fps 60 --scale 24 --out /tmp/out
      mix octopus.recording.encode rec.octorec --no-panels
  """

  use Mix.Task

  alias Octopus.Recording.{Encoder, RadarEncoder}

  @switches [
    out: :string,
    fps: :integer,
    scale: :integer,
    size: :integer,
    panels: :boolean,
    mixed: :boolean,
    ffmpeg: :string
  ]

  @impl Mix.Task
  def run(argv) do
    {opts, args} = OptionParser.parse!(argv, strict: @switches)

    input =
      case args do
        [input | _] -> input
        [] -> Mix.raise("Missing path. Usage: mix octopus.recording.encode PATH")
      end

    cond do
      File.dir?(input) -> encode_session(input, opts)
      File.regular?(input) -> encode_file(input, opts)
      true -> Mix.raise("Recording not found: #{input}")
    end
  end

  defp encode_session(dir, opts) do
    panels = Path.join(dir, "panels.octorec")
    radar = Path.join(dir, "radar.jsonl")

    found? = File.regular?(panels) or File.regular?(radar)

    unless found? do
      Mix.raise("No panels.octorec or radar.jsonl found in session directory: #{dir}")
    end

    # Default the session outputs into the session directory itself.
    opts = Keyword.put_new(opts, :out, dir)

    if File.regular?(panels), do: encode_file(panels, opts)
    if File.regular?(radar), do: encode_file(radar, opts)
  end

  defp encode_file(input, opts) do
    Mix.shell().info("Encoding #{input} ...")

    result =
      case Path.extname(input) do
        ".jsonl" -> RadarEncoder.encode(input, opts)
        _ -> Encoder.encode(input, opts)
      end

    case result do
      {:ok, outputs} ->
        Mix.shell().info("Wrote #{length(outputs)} file(s):")
        Enum.each(outputs, &Mix.shell().info("  #{&1}"))

      {:error, :ffmpeg_not_found} ->
        Mix.raise("""
        ffmpeg was not found on your PATH.

        Install it (e.g. `brew install ffmpeg` on macOS, `apt install ffmpeg` on
        Debian/Ubuntu) or pass an explicit path with --ffmpeg.
        """)

      {:error, :empty_recording} ->
        Mix.raise("Recording contains no frames: #{input}")

      {:error, :invalid_header} ->
        Mix.raise("Not a valid .octorec recording: #{input}")

      {:error, reason} ->
        Mix.raise("Failed to encode recording: #{inspect(reason)}")
    end
  end
end
