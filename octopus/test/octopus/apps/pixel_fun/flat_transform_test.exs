defmodule Octopus.Apps.PixelFun.FlatTransformTest do
  use ExUnit.Case, async: false

  alias Octopus.Apps.PixelFun
  alias Octopus.Apps.PixelFun.Transform.Flat
  alias Octopus.Canvas
  alias Octopus.Installation

  setup do
    original_installation = Application.get_env(:octopus, :installation)

    on_exit(fn ->
      Application.put_env(:octopus, :installation, original_installation)
    end)

    :ok
  end

  defp with_installation(installation, fun) do
    Application.put_env(:octopus, :installation, installation)
    fun.()
  end

  # Minimal renderable state for the current (flat) installation.
  defp flat_render_state(overrides) do
    source = "sin(x*0.7)*cos(y*0.7)"
    {:ok, program} = Octopus.Apps.PixelFun.Program.parse(source)
    w = Installation.width()
    h = Installation.height()

    defaults = %{
      program: program,
      source: source,
      colors: {Chameleon.HSV.new(0, 70, 100), Chameleon.HSV.new(180, 70, 100)},
      display_info: %{width: w, height: h},
      panel_interaction_factors: Map.new(0..(Installation.num_panels() - 1), &{&1, 0.0}),
      seconds: 0.0,
      formula_seconds: 0.0,
      roll_rate: 0.0,
      tilt_scale: 0.0,
      elev_base: 0.0,
      zoom_base: 1.0,
      translate_scale: 0.0,
      pattern_speed: 1.0,
      color_mode: :random,
      saturation_percent: 70,
      audio_input: %{low: 0.0, mid: 0.0, high: 0.0}
    }

    struct(Octopus.Apps.PixelFun.State, Map.merge(defaults, overrides))
  end

  defp build_canvas(state), do: apply(PixelFun, :build_canvas, [state])

  defp max_pixel_diff(c1, c2) do
    for x <- 0..(c1.width - 1), y <- 0..(c1.height - 1), reduce: 0 do
      acc -> max(acc, pixel_diff(Canvas.get_pixel(c1, {x, y}), Canvas.get_pixel(c2, {x, y})))
    end
  end

  defp pixel_diff({r1, g1, b1}, {r2, g2, b2}),
    do: max(abs(r1 - r2), max(abs(g1 - g2), abs(b1 - b2)))

  defp pixel_diff(a, b) when is_integer(a) and is_integer(b), do: abs(a - b)

  describe "transform_backend/0" do
    test "linear installs use flat" do
      with_installation(Octopus.Installation.Pixie, fn ->
        assert PixelFun.transform_backend() == :flat
      end)
    end

    test "circular installs use sphere" do
      with_installation(Octopus.Installation.Nation2026, fn ->
        assert PixelFun.transform_backend() == :sphere
      end)
    end
  end

  describe "mode_tweakables/1 on flat" do
    test "exposes zoom + rotation autos; sway pairs with tilt_scale" do
      with_installation(Octopus.Installation.Pixie, fn ->
        tweaks = PixelFun.mode_tweakables("classic_ripple")

        rotate = Enum.find(tweaks, &(&1.key == :roll_rate))
        zoom = Enum.find(tweaks, &(&1.key == :zoom_base))
        sway = Enum.find(tweaks, &(&1.key == :tilt_scale))
        rot_auto = Enum.find(tweaks, &(&1.key == :rot_auto))

        assert rotate.auto_key == :rot_auto
        assert zoom.auto_key == :zoom_auto
        assert_in_delta zoom.min, 1.0 / 11.0, 0.0001
        assert_in_delta zoom.max, 11.0, 0.0001
        assert sway.auto_key == :sway_auto
        assert rot_auto.companion_of == :roll_rate
        # Rotation is one key in one unit on both backends.
        assert rotate.unit == "°/s"
        refute Enum.any?(tweaks, &(&1.key == :orbit_rate))
        refute Enum.any?(tweaks, &(&1.key == :rotate_scale))
      end)
    end

    test "rot_auto_range keeps its degree sweep meaning on flat" do
      sphere_range =
        with_installation(Octopus.Installation.Nation2026, fn ->
          Enum.find(PixelFun.mode_tweakables("classic_ripple"), &(&1.key == :rot_auto_range))
        end)

      flat_range =
        with_installation(Octopus.Installation.Pixie, fn ->
          Enum.find(PixelFun.mode_tweakables("classic_ripple"), &(&1.key == :rot_auto_range))
        end)

      # One key, one unit. Rescaling this slider per backend (without converting
      # the stored value) is what made preset sweeps run away on flat installs.
      assert flat_range.unit == "°"
      assert flat_range.min == sphere_range.min
      assert flat_range.max == sphere_range.max
      assert flat_range.default == sphere_range.default
    end
  end

  describe "trans_auto on flat" do
    test "pan range scales with the installation instead of the ring" do
      range_max = fn installation ->
        with_installation(installation, fn ->
          PixelFun.mode_tweakables("classic_ripple")
          |> Enum.find(&(&1.key == :trans_auto_range_x))
          |> Map.fetch!(:max)
        end)
      end

      # Half the installation width, both times — the ring keeps the ±156 px
      # this used to hardcode, an 8 px wall gets ±4 instead of panning the
      # pattern clean off the edge.
      assert_in_delta range_max.(Octopus.Installation.Nation2026), 156.0, 0.0001
      assert_in_delta range_max.(Octopus.Installation.Pixie), 4.0, 0.0001
    end

    test "the wandered offset actually reaches the rendered frame" do
      with_installation(Octopus.Installation.Pixie, fn ->
        frame = fn offset ->
          flat_render_state(%{
            trans_auto: true,
            auto_wanderers: %{trans: Octopus.Wander.new({offset, 0.0})}
          })
          |> build_canvas()
        end

        # Flat used to read only translate_scale, so trans_auto moved nothing.
        refute max_pixel_diff(frame.(0.0), frame.(3.0)) == 0
      end)
    end

    test "the same offset renders the same frame while auto is off" do
      with_installation(Octopus.Installation.Pixie, fn ->
        frame = fn offset ->
          flat_render_state(%{
            trans_auto: false,
            auto_wanderers: %{trans: Octopus.Wander.new({offset, 0.0})}
          })
          |> build_canvas()
        end

        # Rendering is deterministic and ignores the wanderer with auto off —
        # without this the test above could pass on noise alone.
        assert max_pixel_diff(frame.(0.0), frame.(3.0)) == 0
      end)
    end
  end

  describe "Flat.rotation_angle/2" do
    test "integrates the manual °/s rate into an absolute angle" do
      # 90 °/s for two seconds is half a turn.
      assert_in_delta Flat.rotation_angle(90.0, 2.0), :math.pi(), 1.0e-9
      assert_in_delta Flat.rotation_angle(0.0, 4.0), 0.0, 1.0e-9
      # Backward time unwinds the rotation rather than advancing it.
      assert_in_delta Flat.rotation_angle(90.0, -2.0), -:math.pi(), 1.0e-9
    end
  end

  describe "Flat.transform_pixel_coords/3" do
    test "uniform zoom scales x and y equally" do
      with_installation(Octopus.Installation.Pixie, fn ->
        params = %{
          offset_x: 0.0,
          offset_y: 0.0,
          zoom: 2.0,
          seconds: 0.0,
          rotation: 0.0,
          sway_scale: 0.0,
          sway_speed: 0.5,
          sway_mode: :wobble
        }

        w = Installation.width()
        h = Installation.height()
        cx = w / 2 - 0.5
        cy = h / 2 - 0.5

        # Point 2 px right of centre → after zoom 2× should be 4 in formula space.
        {x, y} = Flat.transform_pixel_coords(cx + 2.0, cy + 1.0, params)
        assert_in_delta x, 4.0, 0.0001
        assert_in_delta y, 2.0, 0.0001
      end)
    end

    test "PixelFun.dispatch uses flat params on Pixie" do
      with_installation(Octopus.Installation.Pixie, fn ->
        params = %{
          backend: :flat,
          offset_x: 0.0,
          offset_y: 0.0,
          zoom: 1.0,
          seconds: 0.0,
          rotation: 0.0,
          sway_scale: 0.0,
          sway_speed: 0.5,
          sway_mode: :wobble
        }

        w = Installation.width()
        h = Installation.height()
        cx = w / 2 - 0.5
        cy = h / 2 - 0.5

        {x, y} = PixelFun.transform_pixel_coords(cx, cy, params)
        assert_in_delta x, 0.0, 0.0001
        assert_in_delta y, 0.0, 0.0001
      end)
    end
  end
end
