defmodule Octopus.Recording.Format do
  @moduledoc """
  On-disk (and on-the-wire) container format for panel recordings.

  A recording is an append-only stream: a single fixed-size header followed
  by any number of fixed-size frame records. Because the geometry is captured
  once in the header, every record is just a monotonic timestamp plus the raw
  RGB pixel bytes for the whole installation.

  Pixel bytes use the exact same layout the mixer produces for a frame
  (`Octopus.Mixer.canvas_to_frame/4`): **panel-major, then row-major within
  each panel**. For `num_panels` panels of `panel_width x panel_height`, one
  frame is `num_panels * panel_width * panel_height * 3` bytes. Panel `n`
  therefore occupies the contiguous slice
  `[n * panel_bytes, (n + 1) * panel_bytes)` where
  `panel_bytes = panel_width * panel_height * 3`, and each panel slice is a
  ready-to-use RGB image. This is what lets a converter emit one video stream
  per panel (and a mixed stream) without any hardware de-tangling.

  All multi-byte integers are big-endian. Grayscale (`WFrame`) frames are
  normalized to RGB (`r = g = b = w`) before writing so the stream is uniform
  and the converter never needs to branch on frame type.

  ## Header (#{26} bytes)

      magic          8 bytes  "OCTOREC1"
      version        u8       format version
      kind           u8       0 = rgb (only value currently emitted)
      num_panels     u16
      panel_width    u16
      panel_height   u16
      reserved       u16      always 0
      started_at_ms  u64      wall-clock ms (System.system_time/1) at start

  ## Record (`4 + frame_bytes` bytes, repeated)

      offset_ms      u32      System.monotonic_time ms since recording start
      pixels         frame_bytes bytes (RGB, panel-major/row-major)
  """

  @magic "OCTOREC1"
  @version 1
  @kind_rgb 0
  @header_size 26

  @type header :: %{
          version: non_neg_integer(),
          kind: non_neg_integer(),
          num_panels: non_neg_integer(),
          panel_width: non_neg_integer(),
          panel_height: non_neg_integer(),
          started_at_ms: non_neg_integer()
        }

  @doc "The magic bytes every recording starts with."
  @spec magic() :: binary()
  def magic, do: @magic

  @doc "Current format version."
  @spec version() :: non_neg_integer()
  def version, do: @version

  @doc "Size of the fixed header in bytes."
  @spec header_size() :: non_neg_integer()
  def header_size, do: @header_size

  @doc """
  Number of pixel bytes in a single frame for the given geometry (RGB).
  """
  @spec frame_bytes(non_neg_integer(), non_neg_integer(), non_neg_integer()) :: non_neg_integer()
  def frame_bytes(num_panels, panel_width, panel_height),
    do: num_panels * panel_width * panel_height * 3

  @doc "Encode the fixed-size header binary."
  @spec header(pos_integer(), pos_integer(), pos_integer(), non_neg_integer()) :: binary()
  def header(num_panels, panel_width, panel_height, started_at_ms) do
    <<
      @magic::binary,
      @version::8,
      @kind_rgb::8,
      num_panels::16,
      panel_width::16,
      panel_height::16,
      0::16,
      started_at_ms::64
    >>
  end

  @doc """
  Encode a single frame record.

  `rgb_data` must already be RGB pixel bytes of the expected frame size; use
  `normalize/3` to coerce raw mixer frame data into that shape.
  """
  @spec record(non_neg_integer(), binary()) :: binary()
  def record(offset_ms, rgb_data) when is_integer(offset_ms) and is_binary(rgb_data) do
    <<clamp_u32(offset_ms)::32, rgb_data::binary>>
  end

  @doc """
  Coerce raw mixer frame data into RGB pixel bytes of `expected_rgb` size.

    * data already the RGB size -> returned as-is
    * data the grayscale size (1/3 of RGB) -> expanded to `r = g = b = w`
    * anything else -> `:error` (caller should drop the frame)
  """
  @spec normalize(binary(), non_neg_integer(), non_neg_integer()) ::
          {:ok, binary()} | :error
  def normalize(data, expected_rgb, expected_w) when is_binary(data) do
    case byte_size(data) do
      ^expected_rgb -> {:ok, data}
      ^expected_w -> {:ok, expand_w(data)}
      _ -> :error
    end
  end

  @doc "Parse the header from the front of a recording binary."
  @spec parse_header(binary()) :: {:ok, header(), binary()} | {:error, :invalid_header}
  def parse_header(
        <<@magic, version::8, kind::8, num_panels::16, panel_width::16, panel_height::16,
          _reserved::16, started_at_ms::64, rest::binary>>
      ) do
    header = %{
      version: version,
      kind: kind,
      num_panels: num_panels,
      panel_width: panel_width,
      panel_height: panel_height,
      started_at_ms: started_at_ms
    }

    {:ok, header, rest}
  end

  def parse_header(_), do: {:error, :invalid_header}

  @doc """
  Parse a complete recording binary into `{header, records}` where each record
  is `{offset_ms, rgb_data}`. Intended for tests and offline tooling; streaming
  readers should use `parse_header/1` plus their own chunked loop for large
  files.
  """
  @spec parse(binary()) :: {:ok, header(), [{non_neg_integer(), binary()}]} | {:error, term()}
  def parse(binary) when is_binary(binary) do
    with {:ok, header, rest} <- parse_header(binary) do
      fb = frame_bytes(header.num_panels, header.panel_width, header.panel_height)

      case parse_records(fb, rest, []) do
        {:ok, records} -> {:ok, header, records}
        {:error, _} = err -> err
      end
    end
  end

  defp parse_records(_fb, <<>>, acc), do: {:ok, Enum.reverse(acc)}

  defp parse_records(fb, bin, acc) do
    case bin do
      <<offset::32, data::binary-size(^fb), rest::binary>> ->
        parse_records(fb, rest, [{offset, data} | acc])

      _ ->
        {:error, :truncated_record}
    end
  end

  defp expand_w(data) do
    for <<w <- data>>, into: <<>>, do: <<w, w, w>>
  end

  defp clamp_u32(n) when n < 0, do: 0
  defp clamp_u32(n) when n > 0xFFFFFFFF, do: 0xFFFFFFFF
  defp clamp_u32(n), do: n
end
