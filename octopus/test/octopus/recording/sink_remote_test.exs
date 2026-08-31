defmodule Octopus.Recording.Sink.RemoteTest do
  use ExUnit.Case, async: true

  alias Octopus.Recording.Sink.Remote

  test "streams written bytes to a TCP server verbatim" do
    {:ok, listen} =
      :gen_tcp.listen(0, [:binary, packet: :raw, active: false, reuseaddr: true])

    {:ok, port} = :inet.port(listen)
    test_pid = self()

    _acceptor =
      spawn_link(fn ->
        {:ok, sock} = :gen_tcp.accept(listen, 2000)
        send(test_pid, {:received, recv_all(sock, <<>>)})
      end)

    assert {:ok, sink} = Remote.open(host: {127, 0, 0, 1}, port: port)
    assert Remote.describe(sink) == "tcp://127.0.0.1:#{port}"

    assert {:ok, sink} = Remote.write(sink, "HEADER")
    assert {:ok, sink} = Remote.write(sink, <<0, 1, 2, 3>>)
    assert :ok = Remote.close(sink)

    assert_receive {:received, data}, 2000
    assert data == "HEADER" <> <<0, 1, 2, 3>>
  end

  test "open/1 returns an error when the server is unreachable" do
    # Grab a port, then immediately release it so nothing is listening.
    {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(listen)
    :ok = :gen_tcp.close(listen)

    assert {:error, {:connect_failed, _reason}} =
             Remote.open(host: {127, 0, 0, 1}, port: port, connect_timeout: 1000)
  end

  defp recv_all(sock, acc) do
    case :gen_tcp.recv(sock, 0, 2000) do
      {:ok, data} -> recv_all(sock, acc <> data)
      {:error, _} -> acc
    end
  end
end
