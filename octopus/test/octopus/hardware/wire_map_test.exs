defmodule Octopus.Hardware.WireMapTest do
  use ExUnit.Case, async: true

  alias Octopus.Hardware.WireMap

  test "layout and firmware indices are mutual inverses on 0..63" do
    for u <- 0..63 do
      i = WireMap.layout_to_firmware_index(u)
      assert WireMap.firmware_to_layout_index(i) == u
    end

    for i <- 0..63 do
      u = WireMap.firmware_to_layout_index(i)
      assert WireMap.layout_to_firmware_index(u) == i
    end
  end

  test "strip_index matches Display.cpp map_index without SKIP_LEDS" do
    assert WireMap.strip_index(0) == 63
    assert WireMap.strip_index(1) == 62
    assert WireMap.strip_index(8) == 48
    assert WireMap.strip_index(56) == 0
  end

  test "apply_inverse round-trips through firmware ordering" do
    values = Enum.to_list(0..63)

    assert values == values |> WireMap.apply_inverse() |> WireMap.apply_inverse()
  end

  test "apply_strip_inverse maps linear strip layout to firmware buffer order" do
    values = Enum.to_list(0..63)
    encoded = WireMap.apply_strip_inverse(values)

    assert length(encoded) == 64
    assert Enum.at(encoded, WireMap.firmware_index_for_strip(0)) == 0
    assert Enum.at(encoded, WireMap.firmware_index_for_strip(63)) == 63
  end

  test "apply_strip_inverse round-trips with strip index lookup" do
    values = Enum.to_list(0..63)

    encoded = WireMap.apply_strip_inverse(values)

    for strip <- 0..63 do
      firmware_index = WireMap.firmware_index_for_strip(strip)
      assert Enum.at(encoded, firmware_index) == strip
    end
  end

  test "apply_inverse_rgb preserves pixel count" do
    data =
      for i <- 0..63, into: <<>> do
        <<i, i + 1, i + 2>>
      end

    result = WireMap.apply_inverse_rgb(data)
    assert byte_size(result) == 64 * 3
  end
end
