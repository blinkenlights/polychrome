defmodule Octopus.Apps.PixelFun3D.TransformTest do
  use ExUnit.Case, async: false

  alias Octopus.Apps.PixelFun3D
  alias Octopus.Installation
  alias Octopus.Sphere

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

  defp base_params(overrides \\ %{}) do
    Map.merge(
      %{
        seconds: 0.0,
        orbit_rate: 0.0,
        roll_rate: 0.0,
        roll_pivot: 0,
        tilt_scale: 0.0,
        tilt_speed: 0.5,
        tilt_mode: :wobble,
        elev_base: 0.0,
        zoom_base: 1.0,
        zoom_pivot: 0,
        yaw_angle: nil,
        roll_angle: nil
      },
      overrides
    )
  end

  describe "transform_pixel_coords/3 on Nation2026" do
    test "neutral path matches centered canvas coords" do
      with_installation(Octopus.Installation.Nation2026, fn ->
        params = base_params()
        center_x = Installation.width() / 2 - 0.5
        center_y = Installation.height() / 2 - 0.5

        {x_scaled, y_scaled} = PixelFun3D.transform_pixel_coords(center_x, center_y, params)

        assert_in_delta x_scaled, 0.0, 0.0001
        assert_in_delta y_scaled, 0.0, 0.0001
      end)
    end

    test "tilt is W-periodic in chart x for fixed y" do
      with_installation(Octopus.Installation.Nation2026, fn ->
        w = Installation.width()

        params =
          base_params(%{
            tilt_scale: 2.0,
            tilt_speed: 0.5,
            seconds: 1.7,
            tilt_mode: :wobble
          })

        {_x0, y0} = PixelFun3D.transform_pixel_coords(10, 3, params)
        {_x1, y1} = PixelFun3D.transform_pixel_coords(10 + w, 3, params)

        assert_in_delta y0, y1, 0.0001
      end)
    end

    test "negative roll_rate reverses roll" do
      with_installation(Octopus.Installation.Nation2026, fn ->
        forward = base_params(%{roll_rate: 1.0, seconds: 3.0})
        reverse = base_params(%{roll_rate: -1.0, seconds: 3.0})
        mirrored = base_params(%{roll_rate: 1.0, seconds: -3.0})

        {x_forward, y_forward} = PixelFun3D.transform_pixel_coords(50, 3, forward)
        {x_reverse, y_reverse} = PixelFun3D.transform_pixel_coords(50, 3, reverse)
        {x_mirrored, y_mirrored} = PixelFun3D.transform_pixel_coords(50, 3, mirrored)

        assert_in_delta x_reverse, x_mirrored, 0.0001
        assert_in_delta y_reverse, y_mirrored, 0.0001
        refute abs(x_forward - x_reverse) < 0.0001 and abs(y_forward - y_reverse) < 0.0001
      end)
    end

    test "orbit_rate changes sample coords" do
      with_installation(Octopus.Installation.Nation2026, fn ->
        no_orbit = base_params(%{seconds: 3.0})
        with_orbit = base_params(%{orbit_rate: 1.0, seconds: 3.0})

        {x0, y0} = PixelFun3D.transform_pixel_coords(50, 3, no_orbit)
        {x1, y1} = PixelFun3D.transform_pixel_coords(50, 3, with_orbit)

        refute abs(x0 - x1) < 0.0001 and abs(y0 - y1) < 0.0001
      end)
    end

    test "small-angle tilt matches legacy sway offset within 0.02 px" do
      with_installation(Octopus.Installation.Nation2026, fn ->
        w = Installation.width()
        seconds = 1.3
        tilt_scale = 1.0
        tilt_speed = 0.5

        params =
          base_params(%{
            tilt_scale: tilt_scale,
            tilt_speed: tilt_speed,
            tilt_mode: :wobble,
            seconds: seconds
          })

        {amp, phase} = Octopus.Sway.params(tilt_scale, tilt_speed, :wobble, seconds)

        max_dy =
          for x <- 0..(w - 1), rem(x, 26) < 8, reduce: 0.0 do
            acc ->
              {_xs, ys} = PixelFun3D.transform_pixel_coords(x, 3, params)
              cy = Installation.height() / 2 - 0.5
              y_centered = 3 - cy
              legacy_y = y_centered + Octopus.Sway.offset(x, w, amp, phase)
              max(acc, abs(ys - legacy_y))
          end

        assert max_dy < 0.02
      end)
    end

    test "seam: chart x and x+W yield identical formula samples under motion" do
      with_installation(Octopus.Installation.Nation2026, fn ->
        w = Installation.width()
        t = 2.5

        params =
          base_params(%{
            # Display units: legacy 0.4 rad/s → ~19.9 px/s; 0.3 rad/s → ~17.2 °/s; σ0.2 → ×1.22
            orbit_rate: 0.4 * 312 / (:math.pi() * 2),
            roll_rate: 0.3 * 180 / :math.pi(),
            tilt_scale: 1.0,
            elev_base: 0.5,
            zoom_base: :math.exp(0.2),
            seconds: t
          })

        formula = fn xs -> :math.sin(xs * :math.pi() * 6 / 156 - t) end

        for x <- [0, 10, 50, 100, 200] do
          {xs0, _y0} = PixelFun3D.transform_pixel_coords(x, 3, params)
          {xs1, _y1} = PixelFun3D.transform_pixel_coords(x + w, 3, params)
          assert_in_delta formula.(xs0), formula.(xs1), 1.0e-9
        end
      end)
    end

    test "pendulum tilt oscillates with time" do
      with_installation(Octopus.Installation.Nation2026, fn ->
        a =
          base_params(%{
            tilt_scale: 2.0,
            tilt_speed: 1.0,
            tilt_mode: :pendulum,
            seconds: 0.0
          })

        b =
          base_params(%{
            tilt_scale: 2.0,
            tilt_speed: 1.0,
            tilt_mode: :pendulum,
            seconds: :math.pi() / 2
          })

        {_x0, y0} = PixelFun3D.transform_pixel_coords(50, 3, a)
        {_x1, y1} = PixelFun3D.transform_pixel_coords(50, 3, b)

        refute abs(y0 - y1) < 0.0001
      end)
    end
  end

  describe "migrate_legacy_config/1" do
    test "maps sway/rotate/translate to sphere channels and trans_auto" do
      migrated =
        PixelFun3D.migrate_legacy_config(%{
          sway_scale: 1.5,
          sway_speed: 0.8,
          sway_mode: :pendulum,
          rotate_scale: 2.0,
          translate_scale: 3.0,
          zoom_scale: 1.0
        })

      assert migrated.tilt_scale == 1.5
      assert migrated.tilt_speed == 0.8
      assert migrated.tilt_mode == :pendulum
      assert_in_delta migrated.roll_rate, 2.0 * 180 / :math.pi(), 0.1
      assert migrated.trans_auto == true
      assert_in_delta migrated.trans_auto_range_y, 3.0, 0.0001
      assert_in_delta migrated.trans_auto_interval, 60.0, 0.0001
      refute Map.has_key?(migrated, :elev_amp)
      refute Map.has_key?(migrated, :zoom_pulse)
    end

    test "maps elev_amp drift to trans_auto" do
      migrated =
        PixelFun3D.migrate_legacy_config(%{
          elev_amp: 1.5,
          elev_speed: 0.3
        })

      assert migrated.trans_auto == true
      assert_in_delta migrated.trans_auto_range_y, 1.5, 0.0001
      assert_in_delta migrated.trans_auto_interval, 40.0, 0.0001
      refute Map.has_key?(migrated, :elev_amp)
    end

    test "unit migrations: rad/s and log zoom to display units" do
      with_installation(Octopus.Installation.Nation2026, fn ->
        migrated =
          PixelFun3D.migrate_legacy_config(%{
            program: "sin(x)",
            orbit_rate: 0.5,
            roll_rate: 1.0,
            zoom_base: 0.5,
            legacy_internal_units: true
          })

        assert_in_delta migrated.orbit_rate, 0.5 * 312 / (:math.pi() * 2), 0.1
        assert_in_delta migrated.roll_rate, 1.0 * 180 / :math.pi(), 0.1
        assert_in_delta migrated.zoom_base, :math.exp(0.5), 0.1
        assert migrated.pixel_fun_units == 2
      end)
    end

    test "config_matches? succeeds for legacy-unit stored preset vs migrated live" do
      legacy = %{
        program: "sin(0.4*t-hypot(x,y))",
        orbit_rate: 0.5,
        roll_rate: 1.0,
        zoom_base: 0.5,
        color_interval: 5.0,
        palette_auto: true,
        legacy_internal_units: true
      }

      live = PixelFun3D.migrate_legacy_config(legacy)
      assert Octopus.Apps.PixelFun3D.ScenePresets.config_matches?(live, legacy)
    end
  end

  describe "accumulate_orientation_angles/6" do
    test "matches rate*t within 1e-6 over 600 ticks at constant rate" do
      rate = 1.25
      dt = 1 / 60
      ticks = 600

      {yaw, roll} =
        Enum.reduce(1..ticks, {0.0, 0.0}, fn _, {y, r} ->
          PixelFun3D.accumulate_orientation_angles(y, r, rate, rate, dt, dt)
        end)

      t = ticks * dt
      assert_in_delta yaw, rate * t, 1.0e-6
      assert_in_delta roll, rate * t, 1.0e-6
    end
  end

  describe "Sphere direction precompute" do
    test "direction is unit length for visible pixels" do
      with_installation(Octopus.Installation.Nation2026, fn ->
        w = Installation.width()
        h = Installation.height()

        for {x, y} <- List.flatten(Installation.virtual_pixel_positions_per_panel()) do
          assert_in_delta Sphere.norm(Sphere.direction(x, y, w, h)), 1.0, 1.0e-12
        end
      end)
    end
  end
end
