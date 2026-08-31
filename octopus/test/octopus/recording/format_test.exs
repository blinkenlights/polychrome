defmodule Octopus.Recording.FormatTest do
  use ExUnit.Case, async: true

  alias Octopus.Recording.Format

  test "header round-trips through parse_header/1" do
    header = Format.header(12, 8, 8, 1_700_000_000_000)

    assert byte_size(header) == Format.header_size()
    assert {:ok, parsed, <<>>} = Format.parse_header(header)

    assert parsed == %{
             version: Format.version(),
             kind: 0,
             num_panels: 12,
             panel_width: 8,
             panel_height: 8,
             started_at_ms: 1_700_000_000_000
           }
  end

  test "parse_header/1 rejects non-recording binaries" do
    assert {:error, :invalid_header} = Format.parse_header("not a recording")
  end

  test "frame_bytes/3 is num_panels * width * height * 3" do
    assert Format.frame_bytes(12, 8, 8) == 12 * 8 * 8 * 3
  end

  describe "normalize/3" do
    test "passes RGB-sized data through unchanged" do
      rgb = :binary.copy(<<7>>, 12 * 8 * 8 * 3)
      assert {:ok, ^rgb} = Format.normalize(rgb, 12 * 8 * 8 * 3, 12 * 8 * 8)
    end

    test "expands grayscale data to r = g = b = w" do
      w = <<10, 20, 30>>
      assert {:ok, <<10, 10, 10, 20, 20, 20, 30, 30, 30>>} = Format.normalize(w, 9, 3)
    end

    test "returns :error for unexpected sizes" do
      assert :error = Format.normalize(<<1, 2, 3, 4, 5>>, 9, 3)
    end
  end

  test "records round-trip through parse/1 in order" do
    num_panels = 2
    pw = 2
    ph = 2
    frame_bytes = Format.frame_bytes(num_panels, pw, ph)

    a = :binary.copy(<<1>>, frame_bytes)
    b = :binary.copy(<<2>>, frame_bytes)

    binary =
      Format.header(num_panels, pw, ph, 42) <>
        Format.record(0, a) <>
        Format.record(33, b)

    assert {:ok, header, records} = Format.parse(binary)
    assert header.num_panels == num_panels
    assert records == [{0, a}, {33, b}]
  end

  test "parse/1 reports truncated trailing records" do
    binary = Format.header(2, 2, 2, 0) <> <<0::32, 1, 2, 3>>
    assert {:error, :truncated_record} = Format.parse(binary)
  end

  test "record/2 clamps out-of-range offsets into u32" do
    <<offset::32, _::binary>> = Format.record(-5, <<>>)
    assert offset == 0

    <<big::32, _::binary>> = Format.record(0xFFFFFFFF + 100, <<>>)
    assert big == 0xFFFFFFFF
  end
end
