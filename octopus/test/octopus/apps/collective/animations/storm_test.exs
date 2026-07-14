defmodule Octopus.Apps.Collective.Animations.StormTest do
  use ExUnit.Case, async: true

  alias Octopus.Apps.Collective.Animations.Storm
  alias Octopus.Canvas
  alias Octopus.Installation
  alias Octopus.Radar
  alias Octopus.Radar.{Frame, PanelActivity, Track}

  describe "activity_canvas/2" do
    setup do
      start_supervised!(Octopus.Radar.PanelActivity.Settings)
      start_supervised!(PanelActivity)
      :ok
    end

    test "produces grayscale glow when panel activity is present" do
      width = Installation.num_panels() * Installation.panel_width()
      height = Installation.panel_height()
      display_info = %{width: width, height: height, num_panels: Installation.num_panels()}

      frame = %Frame{
        frame_number: 1,
        tracks: [%Track{id: 1, x: 0.0, y: 10.0, z: 0.0, vx: 1.0, vy: 0.0, vz: 0.0}],
        received_at: nil
      }

      send(PanelActivity, {:radar_frame, 1, frame})
      PanelActivity.tick()
      _ = Radar.panel_activity()

      canvas = Storm.activity_canvas(display_info, 0.2)

      assert Enum.any?(
               for x <- 0..(width - 1), y <- 0..(height - 1) do
                 Canvas.get_pixel(canvas, {x, y}) > 0
               end
             )
    end
  end

  describe "render/4 with PanelActivity" do
    setup do
      start_supervised!(Octopus.Radar.PanelActivity.Settings)
      start_supervised!(PanelActivity)
      :ok
    end

    @fast_person %{id: 1, x: 0.0, y: 10.0, vx: 2.0, vy: 0.0}

    defp bolt_pixel_count(canvas) do
      Enum.count(
        for x <- 0..(canvas.width - 1), y <- 0..(canvas.height - 1) do
          {r, g, b} = Canvas.get_pixel(canvas, {x, y})
          r > 100 and g > 100 and b > 180
        end,
        & &1
      )
    end

    defp render_storm_frames(people, reactivity, frames) do
      width = Installation.num_panels() * Installation.panel_width()
      height = Installation.panel_height()
      canvas = Canvas.new(width, height)
      display_info = %{width: width, height: height, num_panels: Installation.num_panels()}

      ctx = %{
        dt: 0.05,
        sensitivity: 3.0,
        background: :deep_dark,
        storm_activity_bleed: 0.2,
        storm_reactivity: reactivity
      }

      state = Storm.init(display_info)

      Enum.reduce(1..frames, {canvas, state}, fn _i, {canvas, state} ->
        Storm.render(canvas, people, ctx, state)
      end)
    end

    test "Crowd Heat 0 is crowd-blind for bolt probability" do
      :rand.seed(:exsss, {42, 42, 42})
      {canvas0, _} = render_storm_frames([@fast_person], 0.0, 30)

      :rand.seed(:exsss, {42, 42, 42})
      {canvas1, _} = render_storm_frames([@fast_person], 0.0, 30)

      assert bolt_pixel_count(canvas0) == bolt_pixel_count(canvas1)
      assert bolt_pixel_count(canvas0) > 0
    end

    test "Crowd Heat 1 dampens bolts when panel activity is low" do
      :rand.seed(:exsss, {7, 7, 7})
      {canvas_blind, _} = render_storm_frames([@fast_person], 0.0, 40)
      blind_bolts = bolt_pixel_count(canvas_blind)

      :rand.seed(:exsss, {7, 7, 7})
      {canvas_cold, _} = render_storm_frames([@fast_person], 1.0, 40)
      cold_bolts = bolt_pixel_count(canvas_cold)

      assert blind_bolts > cold_bolts,
             "expected Crowd Heat 1 with no panel activity to dampen bolts vs Crowd Heat 0"

      frame = %Frame{
        frame_number: 1,
        tracks: [%Track{id: 1, x: 0.0, y: 10.0, z: 0.0, vx: 2.0, vy: 0.0, vz: 0.0}],
        received_at: nil
      }

      send(PanelActivity, {:radar_frame, 1, frame})
      PanelActivity.tick()
      _ = Radar.panel_activity()

      assert Enum.any?(Radar.panel_factors(), fn {_panel, value} -> value > 0.0 end)

      :rand.seed(:exsss, {7, 7, 7})
      {canvas_hot, _} = render_storm_frames([@fast_person], 1.0, 40)
      hot_bolts = bolt_pixel_count(canvas_hot)

      assert hot_bolts >= cold_bolts,
             "expected hot panel activity to restore bolt rate toward Crowd Heat 0"
    end
  end
end
