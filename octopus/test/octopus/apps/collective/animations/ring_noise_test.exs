defmodule Octopus.Apps.Collective.Animations.RingNoiseTest do
  use ExUnit.Case, async: true

  alias Octopus.Apps.Collective.Animations.RingNoise
  alias Octopus.Canvas
  alias Octopus.Installation

  @epsilon 1.0e-9
  @two_pi 2.0 * :math.pi()

  describe "noise/3" do
    test "is seamless at theta = 0 and theta = 2π" do
      for y <- [0.0, 0.9, 3.6, 7.2], t <- [0.0, 1.5, 42.0] do
        left = RingNoise.noise(0.0, y, t)
        right = RingNoise.noise(@two_pi, y, t)
        assert_in_delta left, right, @epsilon
      end
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
        ring_noise_speed: 1.0,
        ring_noise_pulse_period: 24.0,
        ring_noise_pulse_amount: 0.65,
        ring_noise_counter_wave: true,
        ring_noise_palette: :lava
      }

      state = RingNoise.init(display_info)
      {canvas, _state} = RingNoise.render(canvas, [], ctx, state)

      expected = Installation.num_panels() * 64 * 3
      assert byte_size(RingNoise.encode_frame_data(canvas)) == expected
    end
  end
end
