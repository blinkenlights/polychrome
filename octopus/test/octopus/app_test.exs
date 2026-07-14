defmodule Octopus.AppTest do
  use ExUnit.Case, async: false
  alias Octopus.Mixer

  setup do
    # Start the mixer if not already started
    case GenServer.whereis(Mixer) do
      nil -> start_supervised!(Mixer)
      _pid -> :ok
    end

    :ok
  end

  test "get_display_info returns valid display information" do
    # Test the Mixer function directly since we're not in an app process
    display_info = Mixer.get_display_info()

    assert is_integer(display_info.width)
    assert is_integer(display_info.height)
    assert is_integer(display_info.panel_width)
    assert is_integer(display_info.panel_height)
    assert is_integer(display_info.num_panels)
    assert is_integer(display_info.panel_gap)
    assert is_function(display_info.panel_range, 2)
    assert is_function(display_info.panel_at_coord, 2)
  end

  test "display info contains reasonable values" do
    display_info = Mixer.get_display_info()

    # Basic sanity checks
    assert display_info.width > 0
    assert display_info.height > 0
    assert display_info.panel_width > 0
    assert display_info.panel_height > 0
    assert display_info.num_panels > 0
    assert display_info.panel_gap >= 0
  end

  test "panel functions work as expected" do
    display_info = Mixer.get_display_info()

    # Test panel_range for first panel
    {start_x, end_x} = display_info.panel_range.(0, :x)
    {start_y, end_y} = display_info.panel_range.(0, :y)

    assert start_x >= 0
    assert end_x >= start_x
    assert start_y >= 0
    assert end_y >= start_y

    # Test panel_at_coord
    panel_id = display_info.panel_at_coord.(start_x, start_y)
    assert panel_id == 0
  end

  test "derived center values can be calculated" do
    display_info = Mixer.get_display_info()

    # These are the values that PixelFun would calculate
    center_x = display_info.width / 2 - 0.5
    center_y = display_info.height / 2 - 0.5

    assert is_float(center_x)
    assert is_float(center_y)
    assert center_x >= 0
    assert center_y >= 0
  end

  test "app-specific display info with different layouts" do
    original_installation = Application.get_env(:octopus, :installation)
    Application.put_env(:octopus, :installation, Octopus.Installation.Nation2026)

    try do
      Mixer.create_display_buffers(:test_app_gapped, %{layout: :gapped_panels})
      Mixer.create_display_buffers(:test_app_adjacent, %{layout: :adjacent_panels})

      gapped_info = Mixer.get_app_display_info(:test_app_gapped)
      adjacent_info = Mixer.get_app_display_info(:test_app_adjacent)

      assert gapped_info.width != adjacent_info.width
      assert gapped_info.layout == :gapped_panels
      assert adjacent_info.layout == :adjacent_panels

      assert gapped_info.panel_width == adjacent_info.panel_width
      assert gapped_info.panel_height == adjacent_info.panel_height
      assert gapped_info.num_panels == adjacent_info.num_panels
    after
      Application.put_env(:octopus, :installation, original_installation)
    end
  end
end
