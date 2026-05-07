defmodule Octopus.Radar.ProtocolTest do
  use ExUnit.Case, async: true

  alias Octopus.Radar.{Frame, Protocol, Track}

  # The reference frame from manual §25.
  @reference <<
    # HEADER
    0x01,
    0x02,
    0x03,
    0x04,
    0x05,
    0x06,
    0x07,
    0x08,
    # total length = 64
    0x40,
    0x00,
    0x00,
    0x00,
    # frame number = 419
    0xA3,
    0x01,
    0x00,
    0x00,
    # TLV1 = 1
    0x01,
    0x00,
    0x00,
    0x00,
    # point length = 0
    0x00,
    0x00,
    0x00,
    0x00,
    # TLV2 = 2
    0x02,
    0x00,
    0x00,
    0x00,
    # track length = 32
    0x20,
    0x00,
    0x00,
    0x00,
    # ---- track record begin ----
    # reserved
    0x00,
    0x00,
    0x00,
    0x00,
    # id = 0
    0x00,
    0x00,
    0x00,
    0x00,
    # x ≈ -1.1731
    0x21,
    0x28,
    0x96,
    0xBF,
    # y ≈  2.5082
    0xCB,
    0x85,
    0x20,
    0x40,
    # z ≈  0.3197
    0x9A,
    0xAB,
    0xA3,
    0x3E,
    # vx ≈  0.0941
    0x8A,
    0xBD,
    0xC1,
    0x3D,
    # vy ≈ -0.0750
    0x50,
    0x98,
    0x99,
    0xBD,
    # vz ≈  0.0015
    0x40,
    0x52,
    0xC3,
    0x3A,
    # ---- track record end ----
    # checksum
    0xCC
  >>

  describe "parse_frame/1 — manual §25 reference vector" do
    test "decodes the canonical example correctly" do
      assert {:ok, %Frame{} = frame} = Protocol.parse_frame(@reference)

      assert frame.frame_number == 419
      assert length(frame.tracks) == 1

      [%Track{} = track] = frame.tracks
      assert track.id == 0
      assert track.reserved == 0

      assert_in_delta track.x, -1.1731, 1.0e-3
      assert_in_delta track.y, 2.5082, 1.0e-3
      assert_in_delta track.z, 0.3197, 1.0e-3
      assert_in_delta track.vx, 0.0941, 1.0e-3
      assert_in_delta track.vy, -0.0750, 1.0e-3
      assert_in_delta track.vz, 0.0015, 1.0e-3
    end

    test "rejects a frame with a flipped checksum byte" do
      tampered = String.replace_suffix(@reference, <<0xCC>>, <<0xCD>>)
      assert {:error, :checksum_mismatch} = Protocol.parse_frame(tampered)
    end

    test "rejects a frame with the wrong header" do
      <<_::binary-size(8), rest::binary>> = @reference
      bad = <<0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00>> <> rest
      assert {:error, :bad_header} = Protocol.parse_frame(bad)
    end
  end

  describe "feed/2 — stream resync" do
    test "recovers exactly one frame after leading garbage" do
      garbage = <<0xDE, 0xAD, 0xBE, 0xEF, 0x42>>
      stream = garbage <> @reference

      assert {[%Frame{frame_number: 419}], _errors, <<>>} = Protocol.feed(<<>>, stream)
    end

    test "recovers a frame fed byte-by-byte through the stream parser" do
      stream = <<0xAA, 0xBB>> <> @reference

      {frames, _errors, leftover} =
        for byte <- :binary.bin_to_list(stream),
            reduce: {[], [], <<>>} do
          {acc_frames, acc_errors, buffer} ->
            {new_frames, new_errors, new_buffer} = Protocol.feed(buffer, <<byte>>)
            {acc_frames ++ new_frames, acc_errors ++ new_errors, new_buffer}
        end

      assert [%Frame{frame_number: 419}] = frames
      assert leftover == <<>>
    end

    test "two back-to-back frames are both recovered" do
      stream = @reference <> @reference

      assert {[%Frame{frame_number: 419}, %Frame{frame_number: 419}], _errors, <<>>} =
               Protocol.feed(<<>>, stream)
    end

    test "buffer keeps a tail when no header is in sight (waiting for more bytes)" do
      assert {[], [], <<0x01, 0x02, 0x03>>} = Protocol.feed(<<>>, <<0x01, 0x02, 0x03>>)
    end
  end
end
