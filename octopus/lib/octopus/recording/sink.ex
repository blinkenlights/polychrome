defmodule Octopus.Recording.Sink do
  @moduledoc """
  Behaviour for a recording output target.

  A sink is where the raw recording byte stream (header + frame records, see
  `Octopus.Recording.Format`) is written. The recorder is transport-agnostic:
  it opens a sink, writes opaque `iodata` to it, and closes it. This lets the
  same recording pipeline write to a local file today and stream to a remote
  server later without touching the recorder.

  Implementations must be non-blocking enough not to endanger the recorder's
  mailbox. The recorder additionally guards against overload by dropping frames
  when its mailbox grows too large, but a sink should still avoid unbounded
  blocking (e.g. use buffered/delayed writes for files, bounded timeouts for
  network sinks).
  """

  @typedoc "Opaque per-sink state threaded through `write/2` and `close/1`."
  @type state :: term()

  @doc "Open the sink. Returns the initial sink state."
  @callback open(opts :: keyword()) :: {:ok, state()} | {:error, term()}

  @doc "Append bytes to the sink, returning the updated state."
  @callback write(state(), iodata()) :: {:ok, state()} | {:error, term()}

  @doc "Close the sink, flushing any buffered data."
  @callback close(state()) :: :ok

  @doc "Human-readable description of the sink target (for status/logging)."
  @callback describe(state()) :: String.t()
end
