defmodule Octopus.Radar.Protocol do
  @moduledoc """
  Pure-functional parser for the HLK-LD6001A-60G "detailed protocol"
  (`AT+DEBUG=3`) binary stream.

  Implements the byte layout documented in manual §12–§17, including the
  resync state machine described in §15.2/§15.3.

  This module has no process state; the host process owns the byte buffer.

  ## Frame layout

      offset  size  field
           0     8  HEADER (01 02 03 04 05 06 07 08)
           8     4  total length         uint32 little-endian
          12     4  frame number         uint32 little-endian
          16     4  TLV1 (= 1)           uint32 little-endian
          20     4  point cloud length   uint32 little-endian (= 0)
          24     4  TLV2 (= 2)           uint32 little-endian
          28     4  track length         uint32 little-endian
          32     N  N personnel records (32 bytes each)
       32+N      1  XOR checksum

  Note on the `total length` field: the manual's prose says it is "the total
  length of the entire frame", but its own canonical example in §14 shows
  `40 00 00 00` (= 64) for a 65-byte on-wire frame. Empirically — and
  consistently with the structural relationship `total_length = 32 +
  track_length` derived from the fixed prefix — the field **excludes the
  trailing checksum byte**. The example's pseudocode in §17.1 has the same
  off-by-one and would reject the manual's own reference frame. This parser
  follows the example data, not the prose.

  ## Personnel record (32 bytes)

      offset  size  field
           0     4  reserved   uint32 little-endian
           4     4  ID         uint32 little-endian
           8     4  X          float32 little-endian (meters)
          12     4  Y          float32 little-endian (meters)
          16     4  Z          float32 little-endian (meters)
          20     4  Vx         float32 little-endian (m/s)
          24     4  Vy         float32 little-endian (m/s)
          28     4  Vz         float32 little-endian (m/s)

  ## Checksum

  XOR of `frame_number_bytes <> track_data` only. The header, length, TLVs,
  point length, track length and the checksum byte itself are excluded
  (manual §13).
  """

  alias Octopus.Radar.{Frame, Track}

  @header <<1, 2, 3, 4, 5, 6, 7, 8>>
  @header_size 8
  # Size of the fixed prefix from HEADER through TRACKLENTH inclusive.
  # Equals the minimum value of the on-wire `total_length` field (i.e. zero
  # tracks). The on-wire byte count is one larger because the trailing
  # checksum byte is not counted by `total_length`.
  @prefix_size 32
  @record_size 32

  @doc "The 8-byte fixed frame header used to find frame starts in the stream."
  @spec header() :: binary()
  def header, do: @header

  @doc """
  Parse one complete on-wire frame.

  The argument must be exactly one frame (`total_length` bytes). For streaming
  use `feed/2`, which finds frame boundaries and calls this function.
  """
  @spec parse_frame(binary()) :: {:ok, Frame.t()} | {:error, atom()}
  def parse_frame(<<
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
        total_length::little-32,
        frame_number_bytes::binary-size(4),
        tlv1::little-32,
        point_length::little-32,
        tlv2::little-32,
        track_length::little-32,
        rest::binary
      >> = full)
      when byte_size(full) == total_length + 1 do
    cond do
      total_length < @prefix_size ->
        {:error, :frame_too_short}

      tlv1 != 1 ->
        {:error, :unexpected_tlv1}

      tlv2 != 2 ->
        {:error, :unexpected_tlv2}

      point_length != 0 ->
        {:error, :unexpected_point_payload}

      rem(track_length, @record_size) != 0 ->
        {:error, :invalid_track_length}

      total_length != @prefix_size + track_length ->
        {:error, :inconsistent_frame_sizing}

      byte_size(rest) != track_length + 1 ->
        {:error, :truncated_frame}

      true ->
        <<track_data::binary-size(^track_length), checksum>> = rest
        calc = xor_bytes(frame_number_bytes <> track_data)

        if calc == checksum do
          <<frame_number::little-32>> = frame_number_bytes

          {:ok,
           %Frame{
             frame_number: frame_number,
             tracks: parse_tracks(track_data),
             received_at: System.monotonic_time(:millisecond)
           }}
        else
          {:error, :checksum_mismatch}
        end
    end
  end

  def parse_frame(<<1, 2, 3, 4, 5, 6, 7, 8, _::binary>>), do: {:error, :length_mismatch}
  def parse_frame(_), do: {:error, :bad_header}

  @doc """
  Encode a `Frame` into one complete on-wire frame binary.

  Inverse of `parse_frame/1`: lays out the fixed prefix (header, lengths,
  TLVs), one 32-byte personnel record per track, and the trailing XOR
  checksum computed over `frame_number_bytes <> track_data` (manual §13).

  `parse_frame(encode_frame(frame))` reproduces the frame's `frame_number`
  and `tracks` (a track's `:reserved` defaults to 0 and `:received_at` is not
  part of the wire format). Used by `Octopus.Radar.Mock.Server` to emit
  synthetic frames through the real parser.
  """
  @spec encode_frame(Frame.t()) :: binary()
  def encode_frame(%Frame{frame_number: frame_number, tracks: tracks}) do
    track_data = Enum.reduce(tracks, <<>>, fn track, acc -> acc <> encode_track(track) end)
    track_length = byte_size(track_data)
    total_length = @prefix_size + track_length
    frame_number_bytes = <<frame_number::little-32>>
    checksum = xor_bytes(frame_number_bytes <> track_data)

    @header <>
      <<total_length::little-32>> <>
      frame_number_bytes <>
      <<1::little-32, 0::little-32, 2::little-32, track_length::little-32>> <>
      track_data <>
      <<checksum>>
  end

  defp encode_track(%Track{
         reserved: reserved,
         id: id,
         x: x,
         y: y,
         z: z,
         vx: vx,
         vy: vy,
         vz: vz
       }) do
    <<
      (reserved || 0)::little-32,
      id::little-32,
      x::little-float-32,
      y::little-float-32,
      z::little-float-32,
      vx::little-float-32,
      vy::little-float-32,
      vz::little-float-32
    >>
  end

  @doc """
  Stream parser. Append `new_data` to `buffer`, peel off as many complete
  frames as possible, return the parsed frames and the remaining tail.

  Resync per manual §15.3: when bytes precede the next valid header they are
  discarded; when a candidate frame fails validation we advance one byte and
  keep searching. The returned `frames` list contains only successfully
  parsed frames (in stream order). Errors are reported alongside via the
  `errors` list — useful for warning-level logging.

  Returns `{frames, errors, leftover_buffer}`.
  """
  @spec feed(binary(), binary()) ::
          {[Frame.t()], [{:error, atom(), binary()}], binary()}
  def feed(buffer, new_data) when is_binary(buffer) and is_binary(new_data) do
    do_feed(buffer <> new_data, [], [])
  end

  defp do_feed(buffer, frames, errors) do
    case :binary.match(buffer, @header) do
      :nomatch ->
        # Keep at most the last 7 bytes — they could be the start of a header.
        size = byte_size(buffer)
        keep = min(size, @header_size - 1)
        leftover = binary_part(buffer, size - keep, keep)
        {Enum.reverse(frames), Enum.reverse(errors), leftover}

      {0, _} ->
        case extract_frame(buffer) do
          :need_more ->
            {Enum.reverse(frames), Enum.reverse(errors), buffer}

          {:bad_length, advance} ->
            do_feed(binary_part(buffer, advance, byte_size(buffer) - advance), frames, errors)

          {:frame, frame_bin, rest} ->
            case parse_frame(frame_bin) do
              {:ok, frame} ->
                do_feed(rest, [frame | frames], errors)

              {:error, reason} ->
                # Resync: skip one byte and keep scanning so we can recover
                # from corruption in the middle of an otherwise plausible frame.
                <<_, retry::binary>> = buffer
                do_feed(retry, frames, [{:error, reason, frame_bin} | errors])
            end
        end

      {pos, _} ->
        # Drop garbage before the header.
        do_feed(binary_part(buffer, pos, byte_size(buffer) - pos), frames, errors)
    end
  end

  defp extract_frame(buffer) when byte_size(buffer) < @header_size + 4, do: :need_more

  defp extract_frame(<<1, 2, 3, 4, 5, 6, 7, 8, total_length::little-32, _::binary>> = buffer) do
    on_wire_size = total_length + 1

    cond do
      total_length < @prefix_size ->
        # Implausible length — skip past the header and resync.
        {:bad_length, 1}

      byte_size(buffer) < on_wire_size ->
        :need_more

      true ->
        <<frame_bin::binary-size(^on_wire_size), rest::binary>> = buffer
        {:frame, frame_bin, rest}
    end
  end

  defp parse_tracks(<<>>), do: []

  defp parse_tracks(<<
         reserved::little-32,
         id::little-32,
         x::little-float-32,
         y::little-float-32,
         z::little-float-32,
         vx::little-float-32,
         vy::little-float-32,
         vz::little-float-32,
         rest::binary
       >>) do
    [
      %Track{
        id: id,
        reserved: reserved,
        x: x,
        y: y,
        z: z,
        vx: vx,
        vy: vy,
        vz: vz
      }
      | parse_tracks(rest)
    ]
  end

  defp xor_bytes(bin), do: xor_bytes(bin, 0)

  defp xor_bytes(<<>>, acc), do: acc
  defp xor_bytes(<<b, rest::binary>>, acc), do: xor_bytes(rest, Bitwise.bxor(acc, b))
end
