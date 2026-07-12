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
        sink: {:file, []}        # default sink; see below

    The `:sink` spec selects where an auto-started (or default) recording is
  written:

    * `{:file, opts}` - append to a local file (`opts` may set `:dir` or a
      fixed `:path`). This is the default.
    * `{:remote, opts}` - stream to a TCP server; `opts` requires `:host` and
      `:port` (see `Octopus.Recording.Sink.Remote`).

  ## Runtime control

  `start/1`, `stop/0` and `status/0` operate on a whole *session* — the panel
  and radar recorders together, sharing one clock and one session directory
  (see `Octopus.Recording.Session`):

      Octopus.Recording.start()          # -> {:ok, %{dir: ..., panels: ..., radar: ...}}
      Octopus.Recording.start(dir: "/tmp/rec")
      Octopus.Recording.start(radar: false)
      Octopus.Recording.status()
      Octopus.Recording.stop()

  To stream a single stream to a remote server, drive the low-level recorders
  directly:

      Octopus.Recording.PanelRecorder.start_recording(
        sink_mod: Octopus.Recording.Sink.Remote, sink_opts: [host: "10.0.0.5", port: 7000])
  """

  alias Octopus.Recording.Session

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

  @doc """
  Start a recording session (panels + radar). See `Octopus.Recording.Session.start/1`
  for options. Returns `{:ok, %{dir:, panels:, radar:}}` or `{:error, reason}`.
  """
  @spec start(keyword()) :: {:ok, map()} | {:error, term()}
  def start(opts \\ []), do: Session.start(opts)

  @doc "Stop the current session."
  @spec stop() :: :ok | {:error, :not_recording}
  def stop, do: Session.stop()

  @doc "Return the session status map."
  @spec status() :: map()
  def status, do: Session.status()

  @doc "Whether a recording session is currently active."
  @spec recording?() :: boolean()
  def recording?, do: match?(%{active: true}, status())
end
