defmodule Octopus.Apps.PixelFun.TransformTest do
  use ExUnit.Case, async: false

  alias Octopus.Apps.PixelFun
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

  defp base_params(overrides \\ %{}) do
    Map.merge(
      %{
        offset_x: 0.0,
        offset_y: 0.0,
        zoom: 1.0,
        seconds: 0.0,
        rotate_scale: 0.0,
        sway_scale: 0.0,
        sway_speed: 0.5,
        sway_mode: :wobble
      },
      overrides
    )
  end

  describe "transform_pixel_coords/3 on Nation2026" do
    test "sway_scale 0 matches pre-sway transform (no y offset)" do
      with_installation(Octopus.Installation.Nation2026, fn ->
        w = Installation.width()
        params = base_params()

        {x0, y0} = PixelFun.transform_pixel_coords(0, 0, params)
        {x1, y1} = PixelFun.transform_pixel_coords(w, 0, params)

        assert x0 == x1
        assert y0 == y1
      end)
    end

    test "sway is W-periodic in x for fixed y" do
      with_installation(Octopus.Installation.Nation2026, fn ->
        w = Installation.width()

        params =
          base_params(%{
            sway_scale: 2.0,
            sway_speed: 0.5,
            seconds: 1.7,
            sway_mode: :wobble
          })

        {_x0, y0} = PixelFun.transform_pixel_coords(10, 3, params)
        {_x1, y1} = PixelFun.transform_pixel_coords(10 + w, 3, params)

        assert_in_delta y0, y1, 0.0001
      end)
    end

    test "circular rotation keeps y in band (no 2D shear)" do
      with_installation(Octopus.Installation.Nation2026, fn ->
        params =
          base_params(%{
            rotate_scale: 1.0,
            seconds: 3.0,
            zoom: 1.5
          })

        for x <- [0, 50, 150, 300], y <- 0..7 do
          {_x_scaled, y_scaled} = PixelFun.transform_pixel_coords(x, y, params)
          assert y_scaled >= -20 and y_scaled <= 20
        end
      end)
    end

    test "zoom does not scale x on circular ring" do
      with_installation(Octopus.Installation.Nation2026, fn ->
        base = base_params(%{zoom: 1.0})
        zoomed = base_params(%{zoom: 2.5})

        {x_base, _y_base} = PixelFun.transform_pixel_coords(42, 4, base)
        {x_zoomed, _y_zoomed} = PixelFun.transform_pixel_coords(42, 4, zoomed)

        assert_in_delta x_base, x_zoomed, 0.0001
      end)
    end

    test "pendulum mode oscillates sway amplitude" do
      with_installation(Octopus.Installation.Nation2026, fn ->
        at_zero =
          base_params(%{
            sway_scale: 2.0,
            sway_speed: 1.0,
            sway_mode: :pendulum,
            seconds: 0.0
          })

        at_peak =
          base_params(%{
            sway_scale: 2.0,
            sway_speed: 1.0,
            sway_mode: :pendulum,
            seconds: :math.pi() / 2
          })

        {_x, y0} = PixelFun.transform_pixel_coords(20, 2, at_zero)
        {_x, y_peak} = PixelFun.transform_pixel_coords(20, 2, at_peak)

        # Pendulum amplitude is zero at t=0; peak time adds a non-zero y offset.
        center_y = Installation.height() / 2 - 0.5
        y_scaled = 2 - center_y

        assert_in_delta y0, y_scaled, 0.0001
        refute_in_delta y_peak, y_scaled, 0.0001
      end)
    end
  end

  describe "transform_pixel_coords/3 on linear installation" do
    test "keeps 2D rotation semantics" do
      with_installation(Octopus.Installation.RunningLights, fn ->
        no_rot = base_params(%{rotate_scale: 0.0, seconds: 1.0, zoom: 1.0})
        with_rot = base_params(%{rotate_scale: 1.0, seconds: 1.0, zoom: 1.0})

        {x0, y0} = PixelFun.transform_pixel_coords(0, 5, no_rot)
        {x1, y1} = PixelFun.transform_pixel_coords(0, 5, with_rot)

        refute {x0, y0} == {x1, y1}
      end)
    end

    test "zoom scales y only on linear installation" do
      with_installation(Octopus.Installation.RunningLights, fn ->
        base = base_params(%{zoom: 1.0})
        zoomed = base_params(%{zoom: 2.0})

        {x_base, y_base} = PixelFun.transform_pixel_coords(0, 3, base)
        {x_zoomed, y_zoomed} = PixelFun.transform_pixel_coords(0, 3, zoomed)

        assert_in_delta x_base, x_zoomed, 0.0001
        assert abs(y_zoomed) > abs(y_base)
      end)
    end
  end
end
