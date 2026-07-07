defmodule Octopus.Hardware.WireMapTest do
  use ExUnit.Case, async: true

  alias Octopus.Hardware
  alias Octopus.Hardware.WireMap

  @controller Hardware.fetch!(:polychrome_panel_prototype)
  @horizontal Hardware.fetch_wiring!(:serpentine_8x8_bottom_left)
  @vertical Hardware.fetch_wiring!(:serpentine_8x8_vertical_bottom_left)
  @linear_strip Hardware.fetch_wiring!(:linear_strip)

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

  test "vertical wiring maps first LEDs along left column bottom to top" do
    assert WireMap.layout_to_strip(56, @vertical, 8, 8) == 0
    assert WireMap.layout_to_strip(48, @vertical, 8, 8) == 1
    assert WireMap.layout_to_strip(0, @vertical, 8, 8) == 7
    assert WireMap.layout_to_strip(57, @vertical, 8, 8) == 15
    assert WireMap.layout_to_strip(1, @vertical, 8, 8) == 8

    assert WireMap.strip_to_layout(0, @vertical, 8, 8) == 56
    assert WireMap.strip_to_layout(7, @vertical, 8, 8) == 0
    assert WireMap.strip_to_layout(8, @vertical, 8, 8) == 1
    assert WireMap.strip_to_layout(15, @vertical, 8, 8) == 57
  end

  test "vertical layout and strip indices are mutual inverses on 0..63" do
    for u <- 0..63 do
      strip = WireMap.layout_to_strip(u, @vertical, 8, 8)
      assert WireMap.strip_to_layout(strip, @vertical, 8, 8) == u
    end
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

  test "encode_to_firmware horizontal wiring matches apply_inverse" do
    values = Enum.to_list(0..63)

    assert WireMap.encode_to_firmware(values, {8, 8}, @horizontal, @controller) ==
             WireMap.apply_inverse(values)
  end

  test "encode_to_firmware linear strip wiring matches apply_strip_inverse" do
    values = Enum.to_list(0..63)

    assert WireMap.encode_to_firmware(values, {64, 1}, @linear_strip, @controller) ==
             WireMap.apply_strip_inverse(values)
  end

  test "encode_to_firmware vertical wiring differs from horizontal for corner pixels" do
    values = Enum.to_list(0..63)

    horizontal = WireMap.encode_to_firmware(values, {8, 8}, @horizontal, @controller)
    vertical = WireMap.encode_to_firmware(values, {8, 8}, @vertical, @controller)

    refute horizontal == vertical

    bottom_left_firmware_index =
      WireMap.firmware_index_for_layout(0, 7, {8, 8}, @vertical, @controller)

    assert Enum.at(vertical, bottom_left_firmware_index) == 56
    assert Enum.at(vertical, WireMap.firmware_index_for_layout(0, 0, {8, 8}, @vertical, @controller)) == 0
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
