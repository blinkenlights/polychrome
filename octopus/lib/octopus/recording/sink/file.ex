defmodule Octopus.Recording.Sink.File do
  @moduledoc """
  `Octopus.Recording.Sink` that appends the recording stream to a local file.

  Opens the file in `:raw` + `:delayed_write` mode so writes are buffered by
  the runtime and flushed in batches. This keeps per-frame writes cheap (no
  syscall per frame at 60 fps) and avoids blocking the recorder.
  """

  @behaviour Octopus.Recording.Sink

  @impl true
  def open(opts) do
    path = Keyword.fetch!(opts, :path)

    with :ok <- File.mkdir_p(Path.dirname(path)),
         {:ok, io} <- File.open(path, [:write, :binary, :raw, :delayed_write]) do
      {:ok, %{io: io, path: path}}
    end
  end

  @impl true
  def write(%{io: io} = state, iodata) do
    case IO.binwrite(io, iodata) do
      :ok -> {:ok, state}
      other -> {:error, other}
    end
  end

  @impl true
  def close(%{io: io}) do
    _ = File.close(io)
    :ok
  end

  @impl true
  def describe(%{path: path}), do: "file:" <> path
end
