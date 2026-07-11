defmodule Octopus.CanvasTest do
  use ExUnit.Case, async: true

  alias Octopus.Canvas

  describe "new/2" do
    test "creates RGB canvas by default" do
      canvas = Canvas.new(10, 5)
      assert canvas.width == 10
      assert canvas.height == 5
      assert canvas.mode == :rgb
      assert canvas.pixels == %{}
    end

    test "creates RGB canvas explicitly" do
      canvas = Canvas.new(8, 4, :rgb)
      assert canvas.width == 8
      assert canvas.height == 4
      assert canvas.mode == :rgb
      assert canvas.pixels == %{}
    end

    test "creates grayscale canvas" do
      canvas = Canvas.new(6, 3, :grayscale)
      assert canvas.width == 6
      assert canvas.height == 3
      assert canvas.mode == :grayscale
      assert canvas.pixels == %{}
    end
  end

  describe "put_pixel/3 and get_pixel/2" do
    test "RGB mode - puts and gets RGB pixels" do
      canvas = Canvas.new(4, 4, :rgb)
      canvas = Canvas.put_pixel(canvas, {1, 1}, {255, 0, 0})
      canvas = Canvas.put_pixel(canvas, {2, 2}, {0, 255, 0})

      assert Canvas.get_pixel(canvas, {1, 1}) == {255, 0, 0}
      assert Canvas.get_pixel(canvas, {2, 2}) == {0, 255, 0}
      # default black
      assert Canvas.get_pixel(canvas, {0, 0}) == {0, 0, 0}
    end

    test "grayscale mode - puts and gets grayscale pixels" do
      canvas = Canvas.new(4, 4, :grayscale)
      canvas = Canvas.put_pixel(canvas, {1, 1}, 128)
      canvas = Canvas.put_pixel(canvas, {2, 2}, 255)

      assert Canvas.get_pixel(canvas, {1, 1}) == 128
      assert Canvas.get_pixel(canvas, {2, 2}) == 255
      # default black
      assert Canvas.get_pixel(canvas, {0, 0}) == 0
    end

    test "RGB mode - raises error for invalid color" do
      canvas = Canvas.new(4, 4, :rgb)

      assert_raise RuntimeError, ~r/Invalid color.*for mode rgb/, fn ->
        Canvas.put_pixel(canvas, {0, 0}, 128)
      end
    end

    test "grayscale mode - raises error for invalid color" do
      canvas = Canvas.new(4, 4, :grayscale)

      assert_raise RuntimeError, ~r/Invalid color.*for mode grayscale/, fn ->
        Canvas.put_pixel(canvas, {0, 0}, {255, 0, 0})
      end
    end
  end

  describe "fill/2" do
    test "RGB mode - fills with RGB color" do
      canvas = Canvas.new(3, 2, :rgb)
      canvas = Canvas.fill(canvas, {255, 0, 0})

      assert Canvas.get_pixel(canvas, {0, 0}) == {255, 0, 0}
      assert Canvas.get_pixel(canvas, {1, 0}) == {255, 0, 0}
      assert Canvas.get_pixel(canvas, {2, 0}) == {255, 0, 0}
      assert Canvas.get_pixel(canvas, {0, 1}) == {255, 0, 0}
      assert Canvas.get_pixel(canvas, {1, 1}) == {255, 0, 0}
      assert Canvas.get_pixel(canvas, {2, 1}) == {255, 0, 0}
    end

    test "grayscale mode - fills with grayscale color" do
      canvas = Canvas.new(3, 2, :grayscale)
      canvas = Canvas.fill(canvas, 128)

      assert Canvas.get_pixel(canvas, {0, 0}) == 128
      assert Canvas.get_pixel(canvas, {1, 0}) == 128
      assert Canvas.get_pixel(canvas, {2, 0}) == 128
      assert Canvas.get_pixel(canvas, {0, 1}) == 128
      assert Canvas.get_pixel(canvas, {1, 1}) == 128
      assert Canvas.get_pixel(canvas, {2, 1}) == 128
    end
  end

  describe "line/4" do
    test "RGB mode - draws line with RGB color" do
      canvas = Canvas.new(4, 4, :rgb)
      canvas = Canvas.line(canvas, {0, 0}, {3, 3}, {255, 0, 0})

      assert Canvas.get_pixel(canvas, {0, 0}) == {255, 0, 0}
      assert Canvas.get_pixel(canvas, {1, 1}) == {255, 0, 0}
      assert Canvas.get_pixel(canvas, {2, 2}) == {255, 0, 0}
      assert Canvas.get_pixel(canvas, {3, 3}) == {255, 0, 0}
    end

    test "grayscale mode - draws line with grayscale color" do
      canvas = Canvas.new(4, 4, :grayscale)
      canvas = Canvas.line(canvas, {0, 0}, {3, 3}, 128)

      assert Canvas.get_pixel(canvas, {0, 0}) == 128
      assert Canvas.get_pixel(canvas, {1, 1}) == 128
      assert Canvas.get_pixel(canvas, {2, 2}) == 128
      assert Canvas.get_pixel(canvas, {3, 3}) == 128
    end
  end

  describe "rect/4 and fill_rect/4" do
    test "RGB mode - draws rectangle outline" do
      canvas = Canvas.new(4, 4, :rgb)
      canvas = Canvas.rect(canvas, {1, 1}, {2, 2}, {255, 0, 0})

      # Should only have pixels on the border
      assert Canvas.get_pixel(canvas, {1, 1}) == {255, 0, 0}
      assert Canvas.get_pixel(canvas, {2, 1}) == {255, 0, 0}
      assert Canvas.get_pixel(canvas, {2, 2}) == {255, 0, 0}
      assert Canvas.get_pixel(canvas, {1, 2}) == {255, 0, 0}
      # inside should be empty
      assert Canvas.get_pixel(canvas, {0, 0}) == {0, 0, 0}
    end

    test "RGB mode - draws filled rectangle" do
      canvas = Canvas.new(4, 4, :rgb)
      canvas = Canvas.fill_rect(canvas, {1, 1}, {2, 2}, {255, 0, 0})

      # Should have pixels inside the rectangle
      assert Canvas.get_pixel(canvas, {1, 1}) == {255, 0, 0}
      assert Canvas.get_pixel(canvas, {2, 1}) == {255, 0, 0}
      assert Canvas.get_pixel(canvas, {2, 2}) == {255, 0, 0}
      assert Canvas.get_pixel(canvas, {1, 2}) == {255, 0, 0}
      # outside should be empty
      assert Canvas.get_pixel(canvas, {0, 0}) == {0, 0, 0}
    end

    test "grayscale mode - draws rectangle outline" do
      canvas = Canvas.new(4, 4, :grayscale)
      canvas = Canvas.rect(canvas, {1, 1}, {2, 2}, 128)

      assert Canvas.get_pixel(canvas, {1, 1}) == 128
      assert Canvas.get_pixel(canvas, {2, 1}) == 128
      assert Canvas.get_pixel(canvas, {2, 2}) == 128
      assert Canvas.get_pixel(canvas, {1, 2}) == 128
      # inside should be empty
      assert Canvas.get_pixel(canvas, {0, 0}) == 0
    end
  end

  describe "clear/1" do
    test "clears RGB canvas" do
      canvas = Canvas.new(2, 2, :rgb)
      canvas = Canvas.put_pixel(canvas, {0, 0}, {255, 0, 0})
      canvas = Canvas.clear(canvas)

      assert canvas.pixels == %{}
    end

    test "clears grayscale canvas" do
      canvas = Canvas.new(2, 2, :grayscale)
      canvas = Canvas.put_pixel(canvas, {0, 0}, 128)
      canvas = Canvas.clear(canvas)

      assert canvas.pixels == %{}
    end
  end

  describe "to_grayscale/1 and to_rgb/1" do
    test "converts RGB to grayscale" do
      canvas = Canvas.new(2, 2, :rgb)
      # red
      canvas = Canvas.put_pixel(canvas, {0, 0}, {255, 0, 0})
      # green
      canvas = Canvas.put_pixel(canvas, {1, 0}, {0, 255, 0})
      # blue
      canvas = Canvas.put_pixel(canvas, {0, 1}, {0, 0, 255})

      grayscale_canvas = Canvas.to_grayscale(canvas)
      assert grayscale_canvas.mode == :grayscale

      # Check luminance conversion
      red_gray = Canvas.rgb_to_grayscale(255, 0, 0)
      green_gray = Canvas.rgb_to_grayscale(0, 255, 0)
      blue_gray = Canvas.rgb_to_grayscale(0, 0, 255)

      assert Canvas.get_pixel(grayscale_canvas, {0, 0}) == red_gray
      assert Canvas.get_pixel(grayscale_canvas, {1, 0}) == green_gray
      assert Canvas.get_pixel(grayscale_canvas, {0, 1}) == blue_gray
    end

    test "converts grayscale to RGB" do
      canvas = Canvas.new(2, 2, :grayscale)
      canvas = Canvas.put_pixel(canvas, {0, 0}, 128)
      canvas = Canvas.put_pixel(canvas, {1, 0}, 255)

      rgb_canvas = Canvas.to_rgb(canvas)
      assert rgb_canvas.mode == :rgb

      assert Canvas.get_pixel(rgb_canvas, {0, 0}) == {128, 128, 128}
      assert Canvas.get_pixel(rgb_canvas, {1, 0}) == {255, 255, 255}
    end

    test "idempotent conversions" do
      canvas = Canvas.new(2, 2, :rgb)
      canvas = Canvas.put_pixel(canvas, {0, 0}, {255, 0, 0})

      # RGB -> Grayscale -> RGB should be equivalent
      grayscale = Canvas.to_grayscale(canvas)
      back_to_rgb = Canvas.to_rgb(grayscale)

      # The RGB values should be the same (all components equal to grayscale value)
      gray_value = Canvas.rgb_to_grayscale(255, 0, 0)
      assert Canvas.get_pixel(back_to_rgb, {0, 0}) == {gray_value, gray_value, gray_value}
    end
  end

  describe "rgb_to_grayscale/3" do
    test "converts RGB values to grayscale using luminance formula" do
      # Test with standard RGB values
      # red
      assert Canvas.rgb_to_grayscale(255, 0, 0) == 76
      # green
      assert Canvas.rgb_to_grayscale(0, 255, 0) == 149
      # blue
      assert Canvas.rgb_to_grayscale(0, 0, 255) == 29
      # white
      assert Canvas.rgb_to_grayscale(255, 255, 255) == 255
      # black
      assert Canvas.rgb_to_grayscale(0, 0, 0) == 0
      # gray (floating-point precision)
      assert Canvas.rgb_to_grayscale(128, 128, 128) == 127
    end
  end

  describe "blend/4" do
    test "blends RGB canvases" do
      canvas1 = Canvas.new(2, 2, :rgb)
      canvas1 = Canvas.fill(canvas1, {100, 100, 100})

      canvas2 = Canvas.new(2, 2, :rgb)
      canvas2 = Canvas.put_pixel(canvas2, {0, 0}, {200, 200, 200})

      blended = Canvas.blend(canvas2, canvas1, :add, 0.5)
      assert blended.mode == :rgb

      # Should blend the colors
      {r, g, b} = Canvas.get_pixel(blended, {0, 0})
      # (100 * 0.5) + (200 * 0.5)
      assert r == 150
      assert g == 150
      assert b == 150
    end

    test "blends grayscale canvases" do
      canvas1 = Canvas.new(2, 2, :grayscale)
      canvas1 = Canvas.fill(canvas1, 100)

      canvas2 = Canvas.new(2, 2, :grayscale)
      canvas2 = Canvas.put_pixel(canvas2, {0, 0}, 200)

      blended = Canvas.blend(canvas2, canvas1, :add, 0.5)
      assert blended.mode == :grayscale

      # Should blend the colors
      gray_value = Canvas.get_pixel(blended, {0, 0})
      # (100 * 0.5) + (200 * 0.5)
      assert gray_value == 150
    end

    test "raises error when blending canvases with different modes" do
      rgb_canvas = Canvas.new(2, 2, :rgb)
      grayscale_canvas = Canvas.new(2, 2, :grayscale)

      assert_raise RuntimeError, ~r/Cannot blend canvases with different modes/, fn ->
        Canvas.blend(rgb_canvas, grayscale_canvas, :add, 0.5)
      end

      assert_raise RuntimeError, ~r/Cannot blend canvases with different modes/, fn ->
        Canvas.blend(grayscale_canvas, rgb_canvas, :multiply, 0.3)
      end
    end
  end

  describe "bleed/3" do
    defp two_panel_display_info(panel_width \\ 8, panel_gap \\ 4) do
      panel_range = fn panel_id, axis ->
        case axis do
          :x ->
            x_offset = panel_id * (panel_width + panel_gap)
            {x_offset, x_offset + panel_width - 1}

          :y ->
            {0, 7}
        end
      end

      %{
        num_panels: 2,
        panel_range: panel_range
      }
    end

    test "strength 0 leaves canvas unchanged" do
      canvas =
        Canvas.new(20, 8, :rgb)
        |> Canvas.put_pixel({4, 4}, {255, 255, 255})

      display_info = two_panel_display_info()

      assert canvas == Canvas.bleed(canvas, 0.0, display_info: display_info)
    end

    test "RGB white pixel bleeds to neighbors at full strength" do
      canvas =
        Canvas.new(20, 8, :rgb)
        |> Canvas.put_pixel({4, 4}, {255, 255, 255})

      display_info = two_panel_display_info()

      bled = Canvas.bleed(canvas, 50.0, display_info: display_info)

      assert Canvas.get_pixel(bled, {4, 4}) |> elem(0) > 0
      assert Canvas.get_pixel(bled, {4, 3}) |> elem(0) > 0
      assert Canvas.get_pixel(bled, {5, 4}) |> elem(0) > 0
    end

    test "50% reaches the previous maximum bleed strength" do
      canvas =
        Canvas.new(20, 8, :rgb)
        |> Canvas.put_pixel({4, 4}, {255, 255, 255})

      display_info = two_panel_display_info()

      at_50 = Canvas.bleed(canvas, 50.0, display_info: display_info)
      at_100 = Canvas.bleed(canvas, 100.0, display_info: display_info)

      assert Canvas.get_pixel(at_50, {4, 3}) == Canvas.get_pixel(at_100, {4, 3})
    end

    test "bleeding does not cross panel boundaries" do
      panel_width = 8
      panel_gap = 4
      display_info = two_panel_display_info(panel_width, panel_gap)

      canvas =
        Canvas.new(20, 8, :rgb)
        |> Canvas.put_pixel({panel_width - 1, 0}, {255, 255, 255})

      bled = Canvas.bleed(canvas, 100.0, display_info: display_info)

      left_edge_second_panel = panel_width + panel_gap
      assert Canvas.get_pixel(bled, {left_edge_second_panel, 0}) == {0, 0, 0}
    end

    test "grayscale white pixel bleeds to neighbors at full strength" do
      canvas =
        Canvas.new(20, 8, :grayscale)
        |> Canvas.put_pixel({4, 4}, 255)

      display_info = two_panel_display_info()

      bled = Canvas.bleed(canvas, 50.0, display_info: display_info)

      assert Canvas.get_pixel(bled, {4, 4}) > 0
      assert Canvas.get_pixel(bled, {4, 3}) > 0
      assert Canvas.get_pixel(bled, {5, 4}) > 0
    end

    test "returns canvas unchanged without display_info" do
      canvas =
        Canvas.new(8, 8, :rgb)
        |> Canvas.put_pixel({2, 2}, {255, 0, 0})

      assert canvas == Canvas.bleed(canvas, 50.0, [])
    end
  end

  describe "Inspect protocol" do
    test "inspects RGB canvas" do
      canvas = Canvas.new(3, 2, :rgb)
      canvas = Canvas.put_pixel(canvas, {0, 0}, {255, 0, 0})
      canvas = Canvas.put_pixel(canvas, {1, 0}, {0, 255, 0})

      inspect_output = inspect(canvas)
      assert inspect_output =~ "width: 3, height: 2, mode: rgb"
      assert inspect_output =~ "mode: rgb"
    end

    test "inspects grayscale canvas" do
      canvas = Canvas.new(3, 2, :grayscale)
      canvas = Canvas.put_pixel(canvas, {0, 0}, 128)
      canvas = Canvas.put_pixel(canvas, {1, 0}, 255)

      inspect_output = inspect(canvas)
      assert inspect_output =~ "width: 3, height: 2, mode: grayscale"
      assert inspect_output =~ "mode: grayscale"
    end
  end
end
