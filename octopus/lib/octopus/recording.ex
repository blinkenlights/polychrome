defmodule Octopus.Recording do
  @moduledoc """
  Public facade for recording the animations sent to the LED panels.

  Recording captures the mixer's outgoing frames into an append-only file (or,
  later, a remote stream) that can be converted into a video for playback. See
  `Octopus.Recording.PanelRecorder` for the recorder itself and
  `Octopus.Recording.Format` for the on-disk format.

  ## Configuration

      config :octopus, Octopus.Recording,
        enabled: false,          # auto-start a recording on boot
        output_dir: "recordings",# where generated recording files are written
        max_queue: 600,          # mailbox backlog before frames are dropped
        sink: {:file, []},       # default sink; see below
        compress: false,         # gzip the recording stream (see below)
        gzip_level: 6            # zlib level 0..9 when compress: true

    The `:sink` spec selects where an auto-started (or default) recording is
  written:

    * `{:file, opts}` - append to a local file (`opts` may set `:dir` or a
      fixed `:path`). This is the default.
    * `{:remote, opts}` - stream to a TCP server; `opts` requires `:host` and
      `:port` (see `Octopus.Recording.Sink.Remote`).

  When `:compress` is true the stream is gzip-compressed (via built-in `:zlib`,
  no native deps) before hitting the sink; file targets gain a `.gz` suffix. The
  encoders read `.gz` recordings transparently. Lower `:gzip_level` values are
  cheaper on constrained CPUs (e.g. a Raspberry Pi).

  ## Runtime control

      Octopus.Recording.start()          # start recording using the default sink
      Octopus.Recording.start(dir: "/tmp/rec")
      Octopus.Recording.start(sink_mod: Octopus.Recording.Sink.Remote,
        sink_opts: [host: "10.0.0.5", port: 7000])
      Octopus.Recording.status()
      Octopus.Recording.stop()
  """

  alias Octopus.Recording.PanelRecorder

  @default_output_dir "recordings"
  @default_max_queue 600

  @doc "The recording configuration keyword list."
  @spec config() :: keyword()
  def config, do: Application.get_env(:octopus, __MODULE__, [])

  @doc "Whether recording should auto-start on boot."
  @spec enabled?() :: boolean()
  def enabled?, do: config()[:enabled] == true

  @doc "Directory generated recording files are written to."
  @spec output_dir() :: String.t()
  def output_dir, do: config()[:output_dir] || @default_output_dir

  @doc "Mailbox backlog at which the recorder starts dropping frames."
  @spec max_queue() :: pos_integer()
  def max_queue, do: config()[:max_queue] || @default_max_queue

  @doc """
  The configured default sink spec, used for auto-start and when `start/1` is
  called without an explicit `:sink_mod`. Defaults to `{:file, []}`.
  """
  @spec sink_spec() :: {:file, keyword()} | {:remote, keyword()}
  def sink_spec, do: config()[:sink] || {:file, []}

  @doc "Whether recordings should be gzip-compressed. Defaults to false."
  @spec compress?() :: boolean()
  def compress?, do: config()[:compress] == true

  @doc "zlib compression level (0..9) used when `compress?/0` is true. Defaults to 6."
  @spec gzip_level() :: 0..9
  def gzip_level, do: config()[:gzip_level] || 6

  @doc """
  Start recording. See `Octopus.Recording.PanelRecorder.start_recording/1` for
  options. Returns `{:ok, target}` or `{:error, reason}`.
  """
  @spec start(keyword()) :: {:ok, String.t()} | {:error, term()}
  def start(opts \\ []), do: PanelRecorder.start_recording(opts)

  @doc "Stop the current recording."
  @spec stop() :: :ok | {:error, :not_recording}
  def stop, do: PanelRecorder.stop_recording()

  @doc "Return the recorder status map."
  @spec status() :: map()
  def status, do: PanelRecorder.status()

  @doc "Whether a recording is currently active."
  @spec recording?() :: boolean()
  def recording?, do: match?(%{active: true}, status())
end
