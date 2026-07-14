defmodule Octopus.Apps.Collective.Animations.BreathTest do
  use ExUnit.Case, async: true

  alias Octopus.Apps.Collective.Animations.Breath
  alias Octopus.Canvas
  alias Octopus.Installation
  alias Octopus.Radar
  alias Octopus.Radar.{Frame, PanelActivity, Track}

  defp default_ctx(overrides \\ []) do
    Map.merge(
      %{
        dt: 1 / 30,
        breath_liveliness: 0.25,
        breath_layout: :wave,
        breath_palette: :ocean,
        breath_hue_shift: 0.0
      },
      Map.new(overrides)
    )
  end

  describe "crowd normalization" do
    test "three to five walkers read as mid-to-high density" do
      three = for p <- 0..2, into: %{}, do: {p, 0.45}
      five = for p <- 0..4, into: %{}, do: {p, 0.45}

      assert Breath.crowd_density(three) > 0.45
      assert Breath.crowd_density(three) < 0.75
      assert Breath.crowd_density(five) > 0.75
    end

    test "single active panel reads as lively activity" do
      levels = %{0 => 0.42, 1 => 0.0, 2 => 0.0}

      assert Breath.crowd_activity(levels) > 0.85
    end

    test "display_panel_level lifts typical panel factors" do
      assert Breath.display_panel_level(0.42) > 0.9
      assert Breath.display_panel_level(0.0) == 0.0
    end
  end

  describe "render/4" do
    test "produces a non-empty canvas" do
      width = Installation.num_panels() * Installation.panel_width()
      height = Installation.panel_height()
      canvas = Canvas.new(width, height)
      display_info = %{width: width, height: height, num_panels: Installation.num_panels()}

      ctx = default_ctx() |> Map.put(:display_info, display_info)
      state = Breath.init(display_info)
      {canvas, _state} = Breath.render(canvas, [], ctx, state)

      lit? =
        Enum.any?(
          for x <- 0..(width - 1), y <- 0..(height - 1) do
            {r, g, b} = Canvas.get_pixel(canvas, {x, y})
            r + g + b > 0
          end
        )

      assert lit?, "expected visible pixels on an empty room render"
    end

    test "canopy center person raises center_level in state" do
      width = Installation.num_panels() * Installation.panel_width()
      height = Installation.panel_height()
      canvas = Canvas.new(width, height)
      display_info = %{width: width, height: height, num_panels: Installation.num_panels()}

      ctx =
        default_ctx(breath_layout: :canopy, dt: 2.0)
        |> Map.put(:display_info, display_info)

      state = Breath.init(display_info)

      center_person = %{id: 1, x: 0.0, y: 0.0, vx: 0.5, vy: 0.0}

      {_canvas, state} = Breath.render(canvas, [center_person], ctx, state)

      assert state.center_level > 0.0
    end
  end

  describe "render/4 with PanelActivity" do
    setup do
      start_supervised!(Octopus.Radar.PanelActivity.Settings)
      start_supervised!(PanelActivity)
      :ok
    end

    test "panel activity raises column heat in state" do
      width = Installation.num_panels() * Installation.panel_width()
      height = Installation.panel_height()
      canvas = Canvas.new(width, height)
      display_info = %{width: width, height: height, num_panels: Installation.num_panels()}

      ctx =
        default_ctx(dt: 2.0)
        |> Map.put(:display_info, display_info)

      state = Breath.init(display_info)
      {_empty_canvas, empty_state} = Breath.render(canvas, [], ctx, state)

      frame = %Frame{
        frame_number: 1,
        tracks: [%Track{id: 1, x: 0.0, y: 10.0, z: 0.0, vx: 1.0, vy: 0.0, vz: 0.0}],
        received_at: nil
      }

      send(PanelActivity, {:radar_frame, 1, frame})
      PanelActivity.tick()
      _ = Radar.panel_activity()

      assert Enum.any?(Radar.panel_factors(), fn {_panel, value} -> value > 0.0 end)

      {_crowd_canvas, crowd_state} = Breath.render(canvas, [], ctx, empty_state)

      empty_peak = empty_state.heat |> Map.values() |> Enum.max(fn -> 0.0 end)
      crowd_peak = crowd_state.heat |> Map.values() |> Enum.max(fn -> 0.0 end)

      assert crowd_peak > empty_peak,
             "expected panel activity to raise smoothed column heat"
    end

    test "panel activity changes the rendered frame" do
      width = Installation.num_panels() * Installation.panel_width()
      height = Installation.panel_height()
      canvas = Canvas.new(width, height)
      display_info = %{width: width, height: height, num_panels: Installation.num_panels()}

      ctx =
        default_ctx(dt: 2.0)
        |> Map.put(:display_info, display_info)

      state = Breath.init(display_info)
      {empty_frame, state} = Breath.render(canvas, [], ctx, state)

      frame = %Frame{
        frame_number: 1,
        tracks: [%Track{id: 1, x: 0.0, y: 10.0, z: 0.0, vx: 1.0, vy: 0.0, vz: 0.0}],
        received_at: nil
      }

      send(PanelActivity, {:radar_frame, 1, frame})
      PanelActivity.tick()
      _ = Radar.panel_activity()

      {crowd_frame, _state} = Breath.render(canvas, [], ctx, state)

      differs? =
        Enum.any?(
          for x <- 0..(width - 1), y <- 0..(height - 1) do
            Canvas.get_pixel(empty_frame, {x, y}) != Canvas.get_pixel(crowd_frame, {x, y})
          end
        )

      assert differs?, "expected panel activity to change the rendered frame"
    end
  end
end
