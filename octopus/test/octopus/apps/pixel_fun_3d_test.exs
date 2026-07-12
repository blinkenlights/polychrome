defmodule Octopus.TestInstallations.HorizontalStrip64PixelFun3D do
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

defmodule Octopus.Apps.PixelFun3DTest do
  use ExUnit.Case, async: false

  alias Octopus.Apps.PixelFun.Program
  alias Octopus.Apps.PixelFun3D.State
  alias Octopus.Canvas
  alias Octopus.Installation

  @pixel_fun Module.concat(["Octopus", "Apps", "PixelFun3D"])

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
    with_installation(Octopus.TestInstallations.HorizontalStrip64PixelFun3D, fn ->
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
        orbit_rate: 0.0,
        roll_rate: 0.0,
        zoom_base: 0.0,
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
        orbit_rate: 0.0,
        roll_rate: 0.0,
        zoom_base: 0.0,
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
    with_installation(Octopus.TestInstallations.HorizontalStrip64PixelFun3D, fn ->
      {:ok, program} = Program.parse("1")

      state = %State{
        program: program,
        display_info: %{width: Installation.width(), height: Installation.height()},
        colors: {Chameleon.HSV.new(0, 70, 100), Chameleon.HSV.new(180, 70, 100)},
        color_mode: :random,
        panel_proximities: %{0 => 0.0},
        panel_interaction_factors: %{0 => 0.0},
        seconds: 0.0,
        orbit_rate: 0.0,
        roll_rate: 0.0,
        zoom_base: 0.0,
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
    with_installation(Octopus.TestInstallations.HorizontalStrip64PixelFun3D, fn ->
      {:ok, program} = Program.parse("1")

      state = %State{
        program: program,
        display_info: %{width: Installation.width(), height: Installation.height()},
        color_mode: :rainbow,
        panel_proximities: %{0 => 0.0},
        panel_interaction_factors: %{0 => 0.0},
        seconds: 0.0,
        orbit_rate: 0.0,
        roll_rate: 0.0,
        zoom_base: 0.0,
        audio_input: %{low: 0.0, mid: 0.0, high: 0.0}
      }

      canvas = pixel_fun_build_canvas(state)

      assert Canvas.get_pixel(canvas, {0, 0}) != {0, 0, 0}
      assert Canvas.get_pixel(canvas, {63, 0}) != {0, 0, 0}
      assert Canvas.get_pixel(canvas, {0, 0}) != Canvas.get_pixel(canvas, {63, 0})
    end)
  end

  test "build_canvas/1 rainbow mode keeps formula zero black", _context do
    with_installation(Octopus.TestInstallations.HorizontalStrip64PixelFun3D, fn ->
      {:ok, program} = Program.parse("0")

      state = %State{
        program: program,
        display_info: %{width: Installation.width(), height: Installation.height()},
        color_mode: :rainbow,
        panel_proximities: %{0 => 0.0},
        panel_interaction_factors: %{0 => 0.0},
        seconds: 0.0,
        orbit_rate: 0.0,
        roll_rate: 0.0,
        zoom_base: 0.0,
        audio_input: %{low: 0.0, mid: 0.0, high: 0.0}
      }

      canvas = pixel_fun_build_canvas(state)

      for x <- 0..63 do
        assert Canvas.get_pixel(canvas, {x, 0}) == {0, 0, 0}
      end
    end)
  end

  test "build_canvas/1 white mode outputs grayscale integers", _context do
    with_installation(Octopus.TestInstallations.HorizontalStrip64PixelFun3D, fn ->
      {:ok, program} = Program.parse("1")

      state = %State{
        program: program,
        display_info: %{width: Installation.width(), height: Installation.height()},
        color_mode: :white,
        colors: white_levels(100, 50),
        panel_proximities: %{0 => 0.0},
        panel_interaction_factors: %{0 => 0.0},
        seconds: 0.0,
        orbit_rate: 0.0,
        roll_rate: 0.0,
        zoom_base: 0.0,
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
    with_installation(Octopus.TestInstallations.HorizontalStrip64PixelFun3D, fn ->
      {:ok, program} = Program.parse("0")

      state = %State{
        program: program,
        display_info: %{width: Installation.width(), height: Installation.height()},
        color_mode: :white,
        colors: white_levels(100, 50),
        panel_proximities: %{0 => 0.0},
        panel_interaction_factors: %{0 => 0.0},
        seconds: 0.0,
        orbit_rate: 0.0,
        roll_rate: 0.0,
        zoom_base: 0.0,
        audio_input: %{low: 0.0, mid: 0.0, high: 0.0}
      }

      canvas = pixel_fun_build_canvas(state)

      for x <- 0..63 do
        assert Canvas.get_pixel(canvas, {x, 0}) == 0
      end
    end)
  end

  test "build_canvas/1 time_direction backward reverses formula time", _context do
    with_installation(Octopus.TestInstallations.HorizontalStrip64PixelFun3D, fn ->
      {:ok, program} = Program.parse("sin(x-t)")

      base = %{
        program: program,
        display_info: %{width: Installation.width(), height: Installation.height()},
        color_mode: :white,
        colors: white_levels(100, 50),
        panel_proximities: %{0 => 0.0},
        panel_interaction_factors: %{0 => 0.0},
        seconds: 5.0,
        orbit_rate: 0.0,
        roll_rate: 0.0,
        zoom_base: 1.0,
        audio_input: %{low: 0.0, mid: 0.0, high: 0.0}
      }

      # Continuous clock: same wall seconds, opposite formula_seconds after running each way.
      forward =
        struct(State, Map.merge(base, %{time_direction: :forward, formula_seconds: 5.0}))

      backward =
        struct(State, Map.merge(base, %{time_direction: :backward, formula_seconds: -5.0}))

      forward_canvas = pixel_fun_build_canvas(forward)
      backward_canvas = pixel_fun_build_canvas(backward)

      refute Canvas.get_pixel(forward_canvas, {10, 0}) ==
               Canvas.get_pixel(backward_canvas, {10, 0})
    end)
  end

  test "build_canvas/1 white mode maps negative lobe to level_b", _context do
    with_installation(Octopus.TestInstallations.HorizontalStrip64PixelFun3D, fn ->
      {:ok, program} = Program.parse("-1")

      state = %State{
        program: program,
        display_info: %{width: Installation.width(), height: Installation.height()},
        color_mode: :white,
        colors: white_levels(100, 40),
        panel_proximities: %{0 => 0.0},
        panel_interaction_factors: %{0 => 0.0},
        seconds: 0.0,
        orbit_rate: 0.0,
        roll_rate: 0.0,
        zoom_base: 0.0,
        audio_input: %{low: 0.0, mid: 0.0, high: 0.0}
      }

      canvas = pixel_fun_build_canvas(state)

      for x <- 0..63 do
        assert Canvas.get_pixel(canvas, {x, 0}) == 102
      end
    end)
  end

  test "palette_from_phase/3 complementary hues and white gap", _context do
    {a, b} = pixel_fun_palette_from_phase(0.0, :random, 70)
    assert a.h == 0
    assert b.h == 180
    assert a.s == 70

    {a, b} = pixel_fun_palette_from_phase(0.5, :random, 100)
    assert a.h == 180
    assert b.h == 0

    for t <- 0..20 do
      {wa, wb} = pixel_fun_palette_from_phase(t / 20, :white)
      assert abs(wa.v - wb.v) >= 30
      assert wa.v >= 32
      assert wb.v >= 32
    end
  end

  test "mode_tweakables/1 exposes palette phase with auto tempo nest" do
    tweaks = pixel_fun_mode_tweakables("classic_ripple")

    phase = Enum.find(tweaks, &(&1.key == :palette_phase))
    assert phase.label == "Palette"
    assert phase.auto_key == :palette_auto
    assert phase.visible_when == {:color_mode, [:random, :white]}

    tempo = Enum.find(tweaks, &(&1.key == :color_interval))
    assert tempo.label == "Tempo"
    assert tempo.visible_when == {:palette_auto, [true]}
  end

  test "mode_tweakables/1 exposes disabled_when on transform sliders" do
    tweaks = pixel_fun_mode_tweakables("classic_ripple")

    assert Enum.find(tweaks, &(&1.key == :orbit_rate)).disabled_when == {:trans_auto, [true]}
    assert Enum.find(tweaks, &(&1.key == :elev_base)).disabled_when == {:trans_auto, [true]}
    assert Enum.find(tweaks, &(&1.key == :roll_rate)).disabled_when == {:rot_auto, [true]}
    assert Enum.find(tweaks, &(&1.key == :zoom_base)).disabled_when == {:zoom_auto, [true]}
    assert Enum.find(tweaks, &(&1.key == :tilt_scale)).disabled_when == {:sway_auto, [true]}
  end

  test "mode_tweakables/1 exposes saturation with color_mode visibility" do
    spec =
      pixel_fun_mode_tweakables("classic_ripple")
      |> Enum.find(&(&1.key == :saturation_percent))

    assert spec.label == "Saturation"
    assert spec.visible_when == {:color_mode, [:random, :rainbow]}
    assert spec.default == 70
  end

  test "mode_tweakables/1 exposes runtime freeze toggle" do
    spec =
      pixel_fun_mode_tweakables("classic_ripple")
      |> Enum.find(&(&1.key == :time_frozen))

    assert spec.label == "Freeze time"
    assert spec.type == :toggle
    assert spec.runtime == true
  end

  test "mode_tweakables/1 exposes runtime bleeding slider" do
    spec =
      pixel_fun_mode_tweakables("classic_ripple")
      |> Enum.find(&(&1.key == :bleeding))

    assert spec.label == "Bleeding"
    assert spec.type == :slider
    assert spec.unit == "%"
    assert spec.default == 50.0
    assert spec.runtime == true
  end

  test "build_canvas/1 lower saturation produces less vivid colours on random dual", _context do
    with_installation(Octopus.TestInstallations.HorizontalStrip64PixelFun3D, fn ->
      {:ok, program} = Program.parse("1")

      base = %{
        program: program,
        display_info: %{width: Installation.width(), height: Installation.height()},
        color_mode: :random,
        colors: {Chameleon.HSV.new(0, 70, 100), Chameleon.HSV.new(180, 70, 100)},
        panel_proximities: %{0 => 0.0},
        panel_interaction_factors: %{0 => 0.0},
        seconds: 0.0,
        orbit_rate: 0.0,
        roll_rate: 0.0,
        zoom_base: 0.0,
        audio_input: %{low: 0.0, mid: 0.0, high: 0.0}
      }

      muted = pixel_fun_build_canvas(struct(State, Map.put(base, :saturation_percent, 20)))
      vivid = pixel_fun_build_canvas(struct(State, Map.put(base, :saturation_percent, 100)))

      muted_pixel = Canvas.get_pixel(muted, {0, 0})
      vivid_pixel = Canvas.get_pixel(vivid, {0, 0})

      assert muted_pixel != {0, 0, 0}
      assert vivid_pixel != {0, 0, 0}
      assert muted_pixel != vivid_pixel
    end)
  end

  defp white_levels(a, b),
    do: {Chameleon.HSV.new(0, 0, a), Chameleon.HSV.new(0, 0, b)}

  defp pixel_fun_compatible?, do: apply(@pixel_fun, :compatible?, [])
  defp pixel_fun_build_canvas(state), do: apply(@pixel_fun, :build_canvas, [state])
  defp pixel_fun_mode_tweakables(mode_id), do: apply(@pixel_fun, :mode_tweakables, [mode_id])

  defp pixel_fun_palette_from_phase(phase, mode, sat \\ 70),
    do: apply(@pixel_fun, :palette_from_phase, [phase, mode, sat])

  test "nx ny nz are available and unit length in formulas", _context do
    with_installation(Octopus.Installation.Nation2026, fn ->
      {:ok, program} = Program.parse("nx*nx+ny*ny+nz*nz")

      state = %State{
        program: program,
        display_info: %{width: Installation.width(), height: Installation.height()},
        colors: {Chameleon.HSV.new(0, 70, 100), Chameleon.HSV.new(180, 70, 100)},
        color_mode: :random,
        panel_proximities: Map.new(0..(Installation.num_panels() - 1), &{&1, 0.0}),
        panel_interaction_factors: Map.new(0..(Installation.num_panels() - 1), &{&1, 0.0}),
        seconds: 0.0,
        orbit_rate: 0.0,
        roll_rate: 0.0,
        tilt_scale: 0.0,
        elev_base: 0.0,
        zoom_base: 0.0,
        audio_input: %{low: 0.0, mid: 0.0, high: 0.0}
      }

      # Formula returns ~1.0 everywhere → positive lobe → non-black pixels
      canvas = pixel_fun_build_canvas(state)
      {x, y} = hd(List.flatten(Installation.virtual_pixel_positions_per_panel()))
      refute Canvas.get_pixel(canvas, {x, y}) == {0, 0, 0}
    end)
  end

  test "migrate_legacy_config maps old preset keys", _context do
    migrated =
      apply(@pixel_fun, :migrate_legacy_config, [
        %{
          program: "sin(x)",
          sway_scale: 2.0,
          rotate_scale: 1.0,
          translate_scale: 3.0,
          zoom_scale: 1.0
        }
      ])

    assert migrated.tilt_scale == 2.0
    assert_in_delta migrated.roll_rate, 1.0 * 180 / :math.pi(), 0.1
    assert migrated.trans_auto == true
    assert_in_delta migrated.trans_auto_range_y, 3.0, 0.0001
    refute Map.has_key?(migrated, :elev_amp)
    refute Map.has_key?(migrated, :zoom_pulse)
  end
end
