defmodule Octopus.Sound.OSCTest do
  use ExUnit.Case, async: true

  alias Octopus.Sound.OSC

  describe "message/2" do
    test "pads address and type tags to four byte boundaries" do
      # "/s_new" is 6 bytes, so it needs two bytes of padding including the
      # terminator; ",si" likewise.
      assert OSC.message("/s_new", ["pc_ping", 1000]) ==
               "/s_new" <> <<0, 0>> <> ",si" <> <<0>> <> "pc_ping" <> <<0>> <> <<1000::size(32)>>
    end

    test "encodes floats as 32 bit big endian" do
      assert OSC.message("/n_set", [1.0]) ==
               "/n_set" <> <<0, 0>> <> ",f" <> <<0, 0>> <> <<1.0::float-size(32)>>
    end

    test "decodes back with the OSC library used for incoming traffic" do
      decoded = OSC.message("/status") |> OSCx.decode()

      assert decoded.address == "/status"
    end
  end

  describe "bundle/1" do
    test "marks itself for immediate execution" do
      message = OSC.message("/status")
      bundle = OSC.bundle([message])

      assert <<"#bundle", 0, 0::size(32), 1::size(32), size::size(32), rest::binary>> = bundle
      assert size == byte_size(message)
      assert rest == message
    end
  end

  describe "timetag/1" do
    test "counts seconds from the NTP epoch" do
      # 1970-01-01T00:00:00Z is 2208988800 seconds after 1900-01-01.
      assert OSC.timetag(0) == <<2_208_988_800::size(32), 0::size(32)>>
    end

    test "puts sub-second time in the fraction" do
      assert <<seconds::size(32), fraction::size(32)>> = OSC.timetag(500)

      assert seconds == 2_208_988_800
      assert fraction == 2_147_483_648
    end

    test "never lets a rounded fraction overflow into the same second" do
      assert <<seconds::size(32), fraction::size(32)>> = OSC.timetag(999)

      assert seconds == 2_208_988_800
      assert fraction < 4_294_967_296
    end
  end
end
