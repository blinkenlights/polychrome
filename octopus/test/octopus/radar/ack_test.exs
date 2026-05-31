defmodule Octopus.Radar.AckTest do
  use ExUnit.Case, async: true

  alias Octopus.Radar.Ack

  test "clean AT+OK\\r\\n on its own" do
    assert {:ok, <<>>} = Ack.feed(<<>>, "AT+OK\r\n")
  end

  test "AT+OK=3\\r\\n parameter echo" do
    assert {:ok, <<>>} = Ack.feed(<<>>, "AT+OK=3\r\n")
  end

  test "Save Para Fail\\r\\n triggers retry" do
    assert {:retry, <<>>} = Ack.feed(<<>>, "Save Para Fail\r\n")
  end

  test "AT+OK embedded in binary prefix and suffix" do
    prefix = <<0x01, 0x02, 0x03, 0x0A, 0x4B>>
    suffix = <<0xFF, 0xFE>>
    data = prefix <> "AT+OK\r\n" <> suffix

    assert {:ok, ^suffix} = Ack.feed(<<>>, data)
  end

  test "AT+OK split across two feed calls" do
    assert {:pending, buf} = Ack.feed(<<>>, "garbageAT+O")
    assert {:ok, <<>>} = Ack.feed(buf, "K\r\n")
  end

  test "Save Para Fail checked before AT+OK substring" do
    assert {:retry, remainder} = Ack.feed(<<>>, "Save Para Fail\r\nAT+OK\r\n")
    assert remainder == "AT+OK\r\n"
  end

  test "buffer trim keeps recent tail when over max size" do
    noise = :binary.copy(<<0x00>>, 5000)
    data = noise <> "AT+OK\r\n"

    assert {:ok, <<>>} = Ack.feed(<<>>, data)
  end

  test "pending when no response yet" do
    assert {:pending, buf} = Ack.feed(<<>>, <<0x01, 0x02, 0x4B>>)
    assert byte_size(buf) == 3
  end
end
