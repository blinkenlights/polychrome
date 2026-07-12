defmodule Mix.Tasks.Octopus.Recording.Encode do
  @shortdoc "Encode a .octorec panel recording into per-panel and mixed videos"

  @moduledoc """
  Convert a panel recording produced by `Octopus.Recording` into video.

      mix octopus.recording.encode RECORDING.octorec [options]

  By default this writes one video per panel plus a single mixed video (all
  panels laid out side by side) into a directory named after the recording.

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

  alias Octopus.Recording.Encoder

  @switches [
    out: :string,
    fps: :integer,
    scale: :integer,
    panels: :boolean,
    mixed: :boolean,
    ffmpeg: :string
  ]

  @impl Mix.Task
  def run(argv) do
    {opts, args} = OptionParser.parse!(argv, strict: @switches)

    input =
      case args do
        [input | _] ->
          input

        [] ->
          Mix.raise("Missing recording file. Usage: mix octopus.recording.encode FILE.octorec")
      end

    unless File.regular?(input) do
      Mix.raise("Recording file not found: #{input}")
    end

    Mix.shell().info("Encoding #{input} ...")

    case Encoder.encode(input, opts) do
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
