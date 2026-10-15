defmodule Octopus.Recording.Sink.Gzip do
  @moduledoc """
  A composable `Octopus.Recording.Sink` that gzip-compresses the stream and
  forwards the compressed bytes to an inner sink (file or remote).

  Compression uses Erlang's built-in `:zlib`, so there are **no native
  dependencies** — it works out of the box on a Raspberry Pi (and anywhere OTP
  runs). Output is a standard gzip stream, so the resulting files can be read by
  `gunzip`/`zcat` and are decoded transparently by the encoders.

  LED-panel recordings are highly redundant, so gzip typically shrinks them
  substantially (often several-fold, and 10x+ for dark/sparse content); only
  pathological full-frame noise stays near 1:1.

  ## Crash safety

  A gzip stream is only fully valid once finalized on `close/1` (which the
  recorder calls on stop and on normal supervised shutdown). To bound data loss
  from a hard VM crash, the stream is `:sync`-flushed every `:flush_every`
  writes (default #{200}); a sync flush keeps the compression dictionary, so the
  ratio impact is small.

  ## Options

    * `:inner_mod` - the wrapped sink module (required)
    * `:inner_opts` - options passed to the inner sink's `open/1` (default `[]`)
    * `:level` - zlib compression level 0..9 (default #{6}); lower is faster and
      cheaper on constrained CPUs
    * `:flush_every` - sync-flush cadence in writes; `0` disables periodic
      flushing (default #{200})
  """

  @behaviour Octopus.Recording.Sink

  alias Octopus.Recording.Sink

  @default_level 6
  @default_flush_every 200
  # 15-bit window + 16 selects a gzip (not zlib) wrapper.
  @gzip_window_bits 31

  @impl true
  def open(opts) do
    inner_mod = Keyword.fetch!(opts, :inner_mod)
    inner_opts = Keyword.get(opts, :inner_opts, [])
    level = Keyword.get(opts, :level, @default_level)
    flush_every = Keyword.get(opts, :flush_every, @default_flush_every)

    with {:ok, inner} <- inner_mod.open(inner_opts) do
      z = :zlib.open()
      :ok = :zlib.deflateInit(z, level, :deflated, @gzip_window_bits, 8, :default)

      {:ok, %{z: z, inner_mod: inner_mod, inner: inner, flush_every: flush_every, writes: 0}}
    end
  end

  @impl true
  def write(state, iodata) do
    writes = state.writes + 1
    flush = if flush?(state.flush_every, writes), do: :sync, else: :none
    compressed = :zlib.deflate(state.z, iodata, flush)
    state = %{state | writes: writes}

    if IO.iodata_length(compressed) == 0 do
      {:ok, state}
    else
      case state.inner_mod.write(state.inner, compressed) do
        {:ok, inner} -> {:ok, %{state | inner: inner}}
        {:error, _} = err -> err
      end
    end
  end

  @impl true
  def close(state) do
    final = :zlib.deflate(state.z, [], :finish)
    _ = :zlib.deflateEnd(state.z)
    _ = :zlib.close(state.z)

    inner =
      if IO.iodata_length(final) > 0 do
        case state.inner_mod.write(state.inner, final) do
          {:ok, inner} -> inner
          _ -> state.inner
        end
      else
        state.inner
      end

    state.inner_mod.close(inner)
  end

  @impl true
  def describe(state), do: "gzip+" <> state.inner_mod.describe(state.inner)

  @doc """
  Wrap `{sink_mod, sink_opts}` in gzip when `compress?` is true, otherwise return
  it unchanged. For a file sink the target path gains a `.gz` suffix.
  """
  @spec wrap(module(), keyword(), boolean(), non_neg_integer()) :: {module(), keyword()}
  def wrap(sink_mod, sink_opts, compress?, level \\ @default_level)

  def wrap(sink_mod, sink_opts, false, _level), do: {sink_mod, sink_opts}

  def wrap(sink_mod, sink_opts, true, level) do
    {__MODULE__, [inner_mod: sink_mod, inner_opts: gz_path(sink_mod, sink_opts), level: level]}
  end

  defp flush?(0, _writes), do: false
  defp flush?(every, writes), do: rem(writes, every) == 0

  defp gz_path(Sink.File, opts) do
    case Keyword.fetch(opts, :path) do
      {:ok, path} -> Keyword.put(opts, :path, ensure_gz(path))
      :error -> opts
    end
  end

  defp gz_path(_mod, opts), do: opts

  defp ensure_gz(path) do
    if String.ends_with?(path, ".gz"), do: path, else: path <> ".gz"
  end
end
