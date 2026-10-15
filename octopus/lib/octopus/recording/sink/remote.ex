defmodule Octopus.Recording.Sink.Remote do
  @moduledoc """
  `Octopus.Recording.Sink` that streams the recording to a remote server over
  a plain TCP connection.

  The exact same byte stream that would be written to a file (header followed
  by frame records, see `Octopus.Recording.Format`) is sent over the socket, so
  the receiving end can simply append it to a `.octorec` file and later run the
  encoder on it, or convert on the fly.

  ## Safety

  Network I/O must never endanger the running installation. Two bounds keep it
  safe:

    * A connect timeout on `open/1` — an unreachable server fails the
      *recording start*, it does not hang.
    * A send timeout (with `send_timeout_close: true`) on every write — a
      stalled server causes a bounded `{:error, :timeout}` that the recorder
      turns into a clean stop, rather than an indefinite block.

  Because the recorder is a passive PubSub subscriber and drops frames when its
  mailbox backs up, a slow network only degrades the recording (dropped
  frames); the mixer and broadcaster are never affected.

  ## Options

    * `:host` - hostname string, charlist, or IPv4/IPv6 tuple (required)
    * `:port` - TCP port (required)
    * `:connect_timeout` - ms to wait for the connection (default 5000)
    * `:send_timeout` - ms to wait for each write (default 2000)
  """

  @behaviour Octopus.Recording.Sink

  @default_connect_timeout 5_000
  @default_send_timeout 2_000

  @impl true
  def open(opts) do
    host = Keyword.fetch!(opts, :host)
    port = Keyword.fetch!(opts, :port)
    connect_timeout = Keyword.get(opts, :connect_timeout, @default_connect_timeout)
    send_timeout = Keyword.get(opts, :send_timeout, @default_send_timeout)

    tcp_opts = [
      :binary,
      packet: :raw,
      active: false,
      send_timeout: send_timeout,
      send_timeout_close: true
    ]

    case :gen_tcp.connect(resolve_host(host), port, tcp_opts, connect_timeout) do
      {:ok, socket} ->
        {:ok, %{socket: socket, host: host, port: port}}

      {:error, reason} ->
        {:error, {:connect_failed, reason}}
    end
  end

  @impl true
  def write(%{socket: socket} = state, iodata) do
    case :gen_tcp.send(socket, iodata) do
      :ok -> {:ok, state}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def close(%{socket: socket}) do
    _ = :gen_tcp.close(socket)
    :ok
  end

  @impl true
  def describe(%{host: host, port: port}), do: "tcp://#{format_host(host)}:#{port}"

  defp resolve_host(host) when is_tuple(host), do: host
  defp resolve_host(host) when is_binary(host), do: String.to_charlist(host)
  defp resolve_host(host) when is_list(host), do: host

  defp format_host(host) when is_tuple(host) do
    host |> :inet.ntoa() |> to_string()
  end

  defp format_host(host) when is_binary(host), do: host
  defp format_host(host) when is_list(host), do: to_string(host)
end
