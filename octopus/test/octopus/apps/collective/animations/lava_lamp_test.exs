defmodule Octopus.Apps.Collective.Animations.LavaLampTest do
  use ExUnit.Case, async: true

  alias Octopus.Apps.Collective.Animations.LavaLamp
  alias Octopus.Canvas
  alias Octopus.Installation

  @epsilon 1.0e-9
  @two_pi 2.0 * :math.pi()
  @circumference 96

  describe "field_at/6" do
    test "is seamless at theta = 0 and theta = 2π" do
      blobs = LavaLamp.generate_blobs(7)

      for y <- 0..7, t <- [0.0, 3.5, 42.0] do
        left = LavaLamp.field_at(0.0, y, t, blobs, @circumference, 8)
        right = LavaLamp.field_at(@two_pi, y, t, blobs, @circumference, 8)
        assert_in_delta left, right, @epsilon
      end
    end

    test "blob near theta=0.05 lights the seam pixel at x=95" do
      blob = %{
        theta0: 0.05,
        drift: 0.0,
        r: 3.0,
        y_period: 100.0,
        y_phase: 0.0,
        y_amp: 0.0,
        wob_period: 100.0,
        wob_phase: 0.0,
        pulse_period: 100.0,
        pulse_phase: 0.0
      }

      theta_seam = 95 / @circumference * @two_pi
      field_seam = LavaLamp.field_at(theta_seam, 3, 0.0, [blob], @circumference, 8)
      field_far = LavaLamp.field_at(@two_pi / 2, 3, 0.0, [blob], @circumference, 8)

      assert field_seam > 0.5
      assert field_seam > field_far
    end
  end

  describe "render/4" do
    test "produces frame data of num_panels * 64 * 3 bytes" do
      width = Installation.num_panels() * Installation.panel_width()
      height = Installation.panel_height()
      canvas = Canvas.new(width, height)
      display_info = %{width: width, height: height, num_panels: Installation.num_panels()}

      ctx = %{
        dt: 1 / 30,
        lava_blob_count: 7,
        lava_speed: 1.0,
        lava_size_mul: 1.25,
        lava_thresh: 0.9,
        lava_palette: :classic
      }

      state = LavaLamp.init(display_info)
      {canvas, _state} = LavaLamp.render(canvas, [], ctx, state)

      expected = Installation.num_panels() * 64 * 3
      assert byte_size(LavaLamp.encode_frame_data(canvas)) == expected

      # Regression: field scale must leave dark background between blobs.
      dark? =
        Enum.any?(for x <- 0..(width - 1), y <- 0..(height - 1) do
          {r, _, _} = Canvas.get_pixel(canvas, {x, y})
          r < 80
        end)

      assert dark?, "expected dark background pixels, got saturated frame"
    end

    test "pixie-sized canvas is not fully saturated and animates over time" do
      width = 8
      height = 8
      canvas = Canvas.new(width, height)
      display_info = %{width: width, height: height, num_panels: 1}

      ctx = %{
        dt: 0.1,
        lava_blob_count: 5,
        lava_speed: 1.0,
        lava_size_mul: 1.0,
        lava_thresh: 0.9,
        lava_palette: :classic
      }

      state = LavaLamp.init(display_info)
      {canvas_t0, state} = LavaLamp.render(canvas, [], ctx, state)
      {canvas_t1, _} = LavaLamp.render(canvas, [], %{ctx | dt: 2.0}, state)

      dark? =
        Enum.any?(for x <- 0..(width - 1), y <- 0..(height - 1) do
          {r, _, _} = Canvas.get_pixel(canvas_t0, {x, y})
          r < 80
        end)

      changed? =
        Enum.any?(for x <- 0..(width - 1), y <- 0..(height - 1) do
          Canvas.get_pixel(canvas_t0, {x, y}) != Canvas.get_pixel(canvas_t1, {x, y})
        end)

      assert dark?, "expected dark background on 8 px ring"
      assert changed?, "expected blob motion between frames"
    end
  end
end
