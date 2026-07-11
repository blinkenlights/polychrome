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

  test "compatible?/0 for Woodstock 2x32 panels", _context do
    with_installation(Octopus.Installation.Woodstock2, fn ->
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

  test "build_canvas/1 fills all Woodstock panel pixels", _context do
    with_installation(Octopus.Installation.Woodstock2, fn ->
      {:ok, program} = Program.parse("1")

      state = %State{
        program: program,
        display_info: %{width: Installation.width(), height: Installation.height()},
        colors: {Chameleon.HSV.new(0, 70, 100), Chameleon.HSV.new(180, 70, 100)},
        panel_proximities: %{0 => 0.0, 1 => 0.0},
        panel_interaction_factors: %{0 => 0.0, 1 => 0.0},
        seconds: 0.0,
        translate_scale: 0.0,
        rotate_scale: 0.0,
        zoom_scale: 0.0,
        offset: {0, 0},
        audio_input: %{low: 0.0, mid: 0.0, high: 0.0}
      }

      canvas = pixel_fun_build_canvas(state)

      assert {canvas.width, canvas.height} == {36, 32}

      for panel_x <- [0, 34], y <- 0..31, x <- panel_x..(panel_x + 1) do
        assert Canvas.get_pixel(canvas, {x, y}) != {0, 0, 0}
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
        color_mode: :random,
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

  test "build_canvas/1 rainbow mode spreads hues across horizontal strip", _context do
    with_installation(Octopus.TestInstallations.HorizontalStrip64, fn ->
      {:ok, program} = Program.parse("1")

      state = %State{
        program: program,
        display_info: %{width: Installation.width(), height: Installation.height()},
        color_mode: :rainbow,
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

      assert Canvas.get_pixel(canvas, {0, 0}) != {0, 0, 0}
      assert Canvas.get_pixel(canvas, {63, 0}) != {0, 0, 0}
      assert Canvas.get_pixel(canvas, {0, 0}) != Canvas.get_pixel(canvas, {63, 0})
    end)
  end

  test "build_canvas/1 rainbow mode keeps formula zero black", _context do
    with_installation(Octopus.TestInstallations.HorizontalStrip64, fn ->
      {:ok, program} = Program.parse("0")

      state = %State{
        program: program,
        display_info: %{width: Installation.width(), height: Installation.height()},
        color_mode: :rainbow,
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

      for x <- 0..63 do
        assert Canvas.get_pixel(canvas, {x, 0}) == {0, 0, 0}
      end
    end)
  end

  test "build_canvas/1 white mode outputs grayscale integers", _context do
    with_installation(Octopus.TestInstallations.HorizontalStrip64, fn ->
      {:ok, program} = Program.parse("1")

      state = %State{
        program: program,
        display_info: %{width: Installation.width(), height: Installation.height()},
        color_mode: :white,
        colors: white_levels(100, 50),
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

      assert canvas.mode == :grayscale

      for x <- 0..63 do
        assert is_integer(Canvas.get_pixel(canvas, {x, 0}))
        assert Canvas.get_pixel(canvas, {x, 0}) == 255
      end
    end)
  end

  test "build_canvas/1 white mode keeps formula zero black", _context do
    with_installation(Octopus.TestInstallations.HorizontalStrip64, fn ->
      {:ok, program} = Program.parse("0")

      state = %State{
        program: program,
        display_info: %{width: Installation.width(), height: Installation.height()},
        color_mode: :white,
        colors: white_levels(100, 50),
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

      for x <- 0..63 do
        assert Canvas.get_pixel(canvas, {x, 0}) == 0
      end
    end)
  end

  test "build_canvas/1 time_direction backward reverses formula time", _context do
    with_installation(Octopus.TestInstallations.HorizontalStrip64, fn ->
      {:ok, program} = Program.parse("sin(x-t)")

      base = %{
        program: program,
        display_info: %{width: Installation.width(), height: Installation.height()},
        color_mode: :white,
        colors: white_levels(100, 50),
        panel_proximities: %{0 => 0.0},
        panel_interaction_factors: %{0 => 0.0},
        seconds: 5.0,
        translate_scale: 0.0,
        rotate_scale: 0.0,
        zoom_scale: 0.0,
        offset: {0, 0},
        audio_input: %{low: 0.0, mid: 0.0, high: 0.0}
      }

      forward =
        struct(State, Map.put(base, :time_direction, :forward))

      backward =
        struct(State, Map.put(base, :time_direction, :backward))

      forward_canvas = pixel_fun_build_canvas(forward)
      backward_canvas = pixel_fun_build_canvas(backward)

      refute Canvas.get_pixel(forward_canvas, {10, 0}) ==
               Canvas.get_pixel(backward_canvas, {10, 0})
    end)
  end

  test "build_canvas/1 white mode maps negative lobe to level_b", _context do
    with_installation(Octopus.TestInstallations.HorizontalStrip64, fn ->
      {:ok, program} = Program.parse("-1")

      state = %State{
        program: program,
        display_info: %{width: Installation.width(), height: Installation.height()},
        color_mode: :white,
        colors: white_levels(100, 40),
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

      for x <- 0..63 do
        assert Canvas.get_pixel(canvas, {x, 0}) == 102
      end
    end)
  end

  test "generate_random_white_levels/0 respects min gap and min level", _context do
    for _ <- 1..100 do
      {a, b} = pixel_fun_generate_random_white_levels()
      assert abs(a.v - b.v) >= 30
      assert a.v >= 32
      assert b.v >= 32
    end
  end

  defp white_levels(a, b),
    do: {Chameleon.HSV.new(0, 0, a), Chameleon.HSV.new(0, 0, b)}

  defp pixel_fun_compatible?, do: apply(@pixel_fun, :compatible?, [])
  defp pixel_fun_build_canvas(state), do: apply(@pixel_fun, :build_canvas, [state])

  defp pixel_fun_generate_random_white_levels,
    do: apply(@pixel_fun, :generate_random_white_levels, [])
end
