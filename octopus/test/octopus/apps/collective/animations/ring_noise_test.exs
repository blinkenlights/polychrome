defmodule Octopus.Apps.Collective.Animations.RingNoiseTest do
  use ExUnit.Case, async: true

  alias Octopus.Apps.Collective
  alias Octopus.Apps.Collective.Animations.RingNoise
  alias Octopus.Canvas
  alias Octopus.Installation
  alias Octopus.Radar
  alias Octopus.Radar.{Frame, PanelActivity, Track}

  @epsilon 1.0e-9
  @two_pi 2.0 * :math.pi()

  defp base_ctx(overrides \\ %{}) do
    Map.merge(
      %{
        dt: 1 / 30,
        ring_noise_speed: 1.0,
        ring_noise_pulse_period: 24.0,
        ring_noise_pulse_amount: 0.65,
        ring_noise_counter_wave: true,
        ring_noise_palette: :lava,
        ring_noise_crowd_mode: :off,
        ring_noise_reactivity: 0.0,
        ring_noise_crowd_gain: 1.0,
        ring_noise_sat_idle: 0.22,
        ring_noise_activity_bleed: 0.3
      },
      overrides
    )
  end

  defp display_info do
    width = Installation.num_panels() * Installation.panel_width()
    height = Installation.panel_height()
    %{width: width, height: height, num_panels: Installation.num_panels()}
  end

  defp inject_activity! do
    frame = %Frame{
      frame_number: 1,
      tracks: [%Track{id: 1, x: 0.0, y: 10.0, z: 0.0, vx: 1.0, vy: 0.0, vz: 0.0}],
      received_at: nil
    }

    send(PanelActivity, {:radar_frame, 1, frame})
    PanelActivity.tick()
    _ = Radar.panel_activity()

    assert Enum.any?(Radar.panel_factors(), fn {_panel, value} -> value > 0.0 end)
  end

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
      info = display_info()
      canvas = Canvas.new(info.width, info.height)
      state = RingNoise.init(info)

      {canvas, _state} = RingNoise.render(canvas, [], base_ctx(), state)

      expected = Installation.num_panels() * 64 * 3
      assert byte_size(RingNoise.encode_frame_data(canvas)) == expected
    end
  end

  describe "render/4 crowd modes" do
    setup do
      start_supervised!(Octopus.Radar.PanelActivity.Settings)
      start_supervised!(PanelActivity)
      :ok
    end

    test "crowd mode off matches zero reactivity even with panel activity" do
      info = display_info()
      canvas = Canvas.new(info.width, info.height)
      base_state = RingNoise.init(info)
      frozen_ms = :erlang.monotonic_time(:millisecond)
      state = %{base_state | start_ms: frozen_ms}

      off_ctx = base_ctx(%{ring_noise_crowd_mode: :off, ring_noise_reactivity: 0.0})
      blind_ctx = base_ctx(%{ring_noise_crowd_mode: :brightness, ring_noise_reactivity: 0.0})

      {off_frame, _} = RingNoise.render(canvas, [], off_ctx, state)
      inject_activity!()
      {blind_frame, _} = RingNoise.render(canvas, [], blind_ctx, state)

      identical? =
        Enum.all?(
          for x <- 0..(info.width - 1), y <- 0..(info.height - 1) do
            Canvas.get_pixel(off_frame, {x, y}) == Canvas.get_pixel(blind_frame, {x, y})
          end
        )

      assert identical?, "expected crowd-blind frames to match"
    end

    test "brightness mode brightens active panels" do
      info = display_info()
      canvas = Canvas.new(info.width, info.height)
      state = RingNoise.init(info)

      ctx =
        base_ctx(%{
          ring_noise_crowd_mode: :brightness,
          ring_noise_reactivity: 1.0,
          ring_noise_crowd_gain: 1.15,
          ring_noise_palette: :ocean
        })

      {idle_frame, _} = RingNoise.render(canvas, [], ctx, state)
      inject_activity!()
      {crowd_frame, _} = RingNoise.render(canvas, [], ctx, state)

      brighter? =
        Enum.any?(
          for x <- 0..(info.width - 1), y <- 0..(info.height - 1) do
            {r0, g0, b0} = Canvas.get_pixel(idle_frame, {x, y})
            {r1, g1, b1} = Canvas.get_pixel(crowd_frame, {x, y})
            r1 + g1 + b1 > r0 + g0 + b0
          end
        )

      assert brighter?, "expected brightness mode to lift luminance where activity is present"
    end

    test "saturation mode increases chroma on active panels" do
      info = display_info()
      canvas = Canvas.new(info.width, info.height)
      state = RingNoise.init(info)

      ctx =
        base_ctx(%{
          ring_noise_crowd_mode: :saturation,
          ring_noise_reactivity: 1.0,
          ring_noise_sat_idle: 0.20,
          ring_noise_palette: :aurora
        })

      {idle_frame, _} = RingNoise.render(canvas, [], ctx, state)
      inject_activity!()
      {crowd_frame, _} = RingNoise.render(canvas, [], ctx, state)

      more_chroma? =
        Enum.any?(
          for x <- 0..(info.width - 1), y <- 0..(info.height - 1) do
            chroma(idle_frame, x, y) < chroma(crowd_frame, x, y)
          end
        )

      assert more_chroma?, "expected saturation mode to restore colour where activity is present"
    end
  end

  alias Octopus.AppModePresets

  describe "builtin presets" do
    test "includes three ring noise slugs" do
      slugs =
        AppModePresets.list_presets(Collective)
        |> Enum.filter(&(String.starts_with?(&1.slug, "ring_noise")))
        |> Enum.map(& &1.slug)
        |> Enum.sort()

      assert slugs == ["ring_noise", "ring_noise_brightness", "ring_noise_saturation"]
    end

    test "brightness and saturation presets enable crowd modes" do
      brightness = Collective.mode_config("ring_noise_brightness")
      saturation = Collective.mode_config("ring_noise_saturation")
      deco = Collective.mode_config("ring_noise")

      assert Map.get(brightness, :ring_noise_crowd_mode) == :brightness
      assert Map.get(brightness, :ring_noise_reactivity) == 1.0
      assert Map.get(saturation, :ring_noise_crowd_mode) == :saturation
      assert Map.get(saturation, :ring_noise_reactivity) == 1.0
      assert Map.get(deco, :ring_noise_crowd_mode) == :off
      assert Map.get(deco, :ring_noise_reactivity) == 0.0
    end
  end

  defp chroma(canvas, x, y) do
    {r, g, b} = Canvas.get_pixel(canvas, {x, y})
    Enum.max([abs(r - g), abs(g - b), abs(r - b)])
  end
end
