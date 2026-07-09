defmodule Octopus.TestInstallations.HorizontalStrip64 do
  use Octopus.Installation,
    arrangement: :linear,
    panels: [
      [controller: :polychrome_panel_prototype, wiring: :serpentine_horizontal_bottom_left]
    ],
    panel_layout: {64, 1},
    num_buttons: 0,
    num_joysticks: 0,
    panel_gap: 0,
    global_speed: 1.0,
    location: :auto,
    auto_brightness: false,
    network_config: [
      mode: :individual,
      send_in_dev: true
    ],
    simulator_layouts: [
      [
        name: "Horizontal Strip 64",
        mode: "generic",
        pixel_size: {4, 4}
      ]
    ]
end

defmodule Octopus.Apps.PixelFunTest do
  use ExUnit.Case, async: false

  alias Octopus.Apps.PixelFun.Program
  alias Octopus.Apps.PixelFun.State
  alias Octopus.Canvas
  alias Octopus.Installation

  @pixel_fun Module.concat(["Octopus", "Apps", "PixelFun"])

  setup do
    original_installation = Application.get_env(:octopus, :installation)

    on_exit(fn ->
      Application.put_env(:octopus, :installation, original_installation)
    end)

    %{original_installation: original_installation}
  end

  defp with_installation(installation, fun) do
    Application.put_env(:octopus, :installation, installation)
    fun.()
  end

  test "compatible?/0 for Running Lights vertical strip", _context do
    with_installation(Octopus.Installation.RunningLights, fn ->
      assert pixel_fun_compatible?()
    end)
  end

  test "compatible?/0 for Prototype 8x8", _context do
    with_installation(Octopus.Installation.Prototype, fn ->
      assert pixel_fun_compatible?()
    end)
  end

  test "compatible?/0 for horizontal strip 64x1", _context do
    with_installation(Octopus.TestInstallations.HorizontalStrip64, fn ->
      assert pixel_fun_compatible?()
    end)
  end

  test "build_canvas/1 fills all vertical strip pixels on Running Lights", _context do
    with_installation(Octopus.Installation.RunningLights, fn ->
      {:ok, program} = Program.parse("1")

      state = %State{
        program: program,
        display_info: %{width: Installation.width(), height: Installation.height()},
        colors: {Chameleon.HSV.new(0, 70, 100), Chameleon.HSV.new(180, 70, 100)},
        panel_proximities: %{0 => 0.0},
        panel_interaction_factors: %{0 => 0.0},
        seconds: 0.0,
        translate_scale: 0.0,
        rotate_scale: 0.0,
        zoom_scale: 0.0,
        offset: {0, 0},
        audio_input: %{low: 0.0, mid: 0.0, high: 0.0}
      }

      canvas = pixel_fun_build_canvas(state)

      assert {canvas.width, canvas.height} == {1, 24}

      for y <- 0..23 do
        assert Canvas.get_pixel(canvas, {0, y}) != {0, 0, 0}
      end
    end)
  end

  test "build_canvas/1 fills all horizontal strip pixels on 64x1", _context do
    with_installation(Octopus.TestInstallations.HorizontalStrip64, fn ->
      {:ok, program} = Program.parse("1")

      state = %State{
        program: program,
        display_info: %{width: Installation.width(), height: Installation.height()},
        colors: {Chameleon.HSV.new(0, 70, 100), Chameleon.HSV.new(180, 70, 100)},
        panel_proximities: %{0 => 0.0},
        panel_interaction_factors: %{0 => 0.0},
        seconds: 0.0,
        translate_scale: 0.0,
        rotate_scale: 0.0,
        zoom_scale: 0.0,
        offset: {0, 0},
        audio_input: %{low: 0.0, mid: 0.0, high: 0.0}
      }

      canvas = pixel_fun_build_canvas(state)

      assert {canvas.width, canvas.height} == {64, 1}

      for x <- 0..63 do
        assert Canvas.get_pixel(canvas, {x, 0}) != {0, 0, 0}
      end
    end)
  end

  defp pixel_fun_compatible?, do: apply(@pixel_fun, :compatible?, [])
  defp pixel_fun_build_canvas(state), do: apply(@pixel_fun, :build_canvas, [state])
end
