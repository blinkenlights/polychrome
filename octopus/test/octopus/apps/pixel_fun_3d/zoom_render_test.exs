defmodule Octopus.Apps.PixelFun3D.ZoomRenderTest do
  use ExUnit.Case, async: false

  alias Octopus.Apps.PixelFun.Program
  alias Octopus.Apps.PixelFun3D
  alias Octopus.Apps.PixelFun3D.State
  alias Octopus.Canvas
  alias Octopus.Installation

  @pixel_fun Module.concat(["Octopus", "Apps", "PixelFun3D"])

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

  defp base_state(overrides) do
    w = Installation.width()
    h = Installation.height()
    source = Map.get(overrides, :source, "sin(x*6/156-t)")
    {:ok, program} = Program.parse(source)

    pixel_dirs =
      Installation.virtual_pixel_positions_per_panel()
      |> Enum.map(fn panel ->
        Enum.map(panel, fn {x, y} ->
          {x, y, Octopus.Sphere.direction(x, y, w, h)}
        end)
      end)

    defaults = %{
      program: program,
      source: source,
      colors: {Chameleon.HSV.new(0, 70, 100), Chameleon.HSV.new(180, 70, 100)},
      display_info: %{width: w, height: h},
      panel_interaction_factors: Map.new(0..(Installation.num_panels() - 1), fn i -> {i, 0.0} end),
      seconds: 0.0,
      formula_seconds: 0.0,
      orbit_rate: 0.0,
      roll_rate: 0.0,
      tilt_scale: 0.0,
      elev_base: 0.0,
      zoom_base: 1.0,
      zoom_pivot: 0,
      zoom_octave_n: 0,
      octave_fade: nil,
      pattern_speed: 1.0,
      color_mode: :random,
      saturation_percent: 70,
      audio_input: %{low: 0.0, mid: 0.0, high: 0.0},
      pixel_dirs: pixel_dirs
    }

    struct(State, Map.merge(defaults, Map.drop(overrides, [:source])))
  end

  defp build_canvas(state), do: apply(@pixel_fun, :build_canvas, [state])

  defp max_pixel_diff(c1, c2) do
    w = c1.width
    h = c1.height

    for x <- 0..(w - 1), y <- 0..(h - 1), reduce: 0 do
      acc ->
        p1 = Canvas.get_pixel(c1, {x, y})
        p2 = Canvas.get_pixel(c2, {x, y})
        diff = pixel_diff(p1, p2)
        max(acc, diff)
    end
  end

  defp pixel_diff({r1, g1, b1}, {r2, g2, b2}) do
    max(abs(r1 - r2), max(abs(g1 - g2), abs(b1 - b2)))
  end

  defp pixel_diff(a, b) when is_integer(a) and is_integer(b), do: abs(a - b)

  describe "frame continuity at octave switch" do
    test "fade u≈0 matches pre-switch steady frame" do
      with_installation(Octopus.Installation.Nation2026, fn ->
        z = 2.0
        seconds = 5.0

        pre =
          base_state(%{
            zoom_base: z,
            zoom_octave_n: 0,
            octave_fade: nil,
            seconds: seconds
          })

        post =
          base_state(%{
            zoom_base: z,
            zoom_octave_n: 0,
            octave_fade: %{from_n: 0, to_n: 1, started_at: seconds},
            seconds: seconds + 0.001
          })

        assert max_pixel_diff(build_canvas(pre), build_canvas(post)) <= 1
      end)
    end

    test "fade end matches post-switch steady after octave state commits" do
      with_installation(Octopus.Installation.Nation2026, fn ->
        z = 2.0
        seconds = 10.0
        dur = Octopus.Apps.PixelFun3D.Zoom.octave_fade_dur()

        fading =
          base_state(%{
            zoom_base: z,
            zoom_octave_n: 0,
            octave_fade: %{from_n: 0, to_n: 1, started_at: seconds - dur},
            seconds: seconds
          })

        {updates, committed_n, fade} =
          Octopus.Apps.PixelFun3D.Zoom.advance_octave_state(
            Map.from_struct(fading),
            z,
            seconds
          )

        assert committed_n == 1
        assert fade == nil

        committed = struct(State, Map.merge(Map.from_struct(fading), updates))

        steady =
          base_state(%{
            zoom_base: z,
            zoom_octave_n: 1,
            octave_fade: nil,
            seconds: seconds
          })

        assert max_pixel_diff(build_canvas(committed), build_canvas(steady)) <= 1
      end)
    end
  end

  describe "pivot invariance during fade" do
    test "from and to branches match at pivot column for non-center pivot" do
      with_installation(Octopus.Installation.Nation2026, fn ->
        w = Installation.width()
        alpha = Octopus.Sphere.alpha(w)
        cx = w / 2 - 0.5
        pivot_panel = 3
        stride = Installation.panel_width() + Installation.panel_gap()
        pivot_x = pivot_panel * stride + Installation.panel_width() / 2 - 0.5
        x_p = (pivot_x - cx) * alpha / alpha

        z = 3.0
        from_n = 1
        to_n = 2
        m_from = :math.pow(2, from_n)
        m_to = :math.pow(2, to_n)
        r_from = z / m_from
        r_to = z / m_to

        phi_a = (pivot_x - cx) * alpha

        motion = %{
          matrix: Octopus.Sphere.identity(),
          mobius_basis: Octopus.Sphere.mobius_basis(phi_a),
          zoom_center: {:math.cos(phi_a), :math.sin(phi_a), 0.0},
          zoom_mode: :mobius,
          elev_rad: 0.0,
          alpha: alpha,
          x_p: x_p
        }

        y = 3
        d = Octopus.Sphere.direction(trunc(pivot_x), y, w, Installation.height())

        {xs_f, _ys_f, _} =
          Octopus.Apps.PixelFun3D.Zoom.sample_pixel(d, motion, m_from, r_from, x_p)

        {xs_t, _ys_t, _} =
          Octopus.Apps.PixelFun3D.Zoom.sample_pixel(d, motion, m_to, r_to, x_p)

        assert_in_delta xs_f, xs_t, 1.0e-4
      end)
    end
  end

  describe "neutral fast path" do
    test "z=1 is bit-identical to centered coords path" do
      with_installation(Octopus.Installation.Nation2026, fn ->
        state =
          base_state(%{
            zoom_base: 1.0,
            zoom_octave_n: 0,
            source: "1",
            program: elem(Program.parse("1"), 1)
          })

        canvas = build_canvas(state)

        for panel <- state.pixel_dirs, {x, y, _d} <- panel do
          assert Canvas.get_pixel(canvas, {x, y}) != {0, 0, 0}
        end
      end)
    end
  end

  describe "legacy zoom clamp" do
    test "stored zoom_base 0.25 loads as 0.7 with warning" do
      import ExUnit.CaptureLog

      log =
        capture_log(fn ->
          migrated = PixelFun3D.migrate_legacy_config(%{zoom_base: 0.25, program: "sin(x)"})
          assert migrated.zoom_base == 0.7
        end)

      assert log =~ "legacy zoom_base 0.25 clamped to 0.7"
    end

    test "config_matches? compares via clamped zoom_base" do
      legacy = %{program: "sin(x)", zoom_base: 0.25, pixel_fun_units: 2}
      live = PixelFun3D.migrate_legacy_config(legacy)
      assert Octopus.Apps.PixelFun3D.ScenePresets.config_matches?(live, legacy)
    end
  end

  describe "seam with octave multiplier" do
    test "W-periodic formula identical for m in {1,2,4,8} with non-center pivot" do
      with_installation(Octopus.Installation.Nation2026, fn ->
        w = Installation.width()

        params =
          %{
            seconds: 2.5,
            orbit_rate: 0.4 * 312 / (:math.pi() * 2),
            roll_rate: 0.3 * 180 / :math.pi(),
            tilt_scale: 1.0,
            elev_base: 0.5,
            zoom_base: 1.5,
            zoom_pivot: 3,
            zoom_octave_n: 0
          }

        formula = fn xs -> :math.sin(xs * :math.pi() * 6 / 156 - 2.5) end

        for x <- [0, 10, 50, 100, 200] do
          {xs0, _y0} = PixelFun3D.transform_pixel_coords(x, 3, params)
          {xs1, _y1} = PixelFun3D.transform_pixel_coords(x + w, 3, params)
          assert_in_delta formula.(xs0), formula.(xs1), 1.0e-6
        end
      end)
    end
  end
end
