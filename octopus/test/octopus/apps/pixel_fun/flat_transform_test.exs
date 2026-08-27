defmodule Octopus.Apps.PixelFun.FlatTransformTest do
  use ExUnit.Case, async: false

  alias Octopus.Apps.PixelFun
  alias Octopus.Apps.PixelFun.Transform.Flat
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

        rotate = Enum.find(tweaks, &(&1.key == :rotate_scale))
        zoom = Enum.find(tweaks, &(&1.key == :zoom_base))
        sway = Enum.find(tweaks, &(&1.key == :tilt_scale))
        rot_auto = Enum.find(tweaks, &(&1.key == :rot_auto))

        assert rotate.auto_key == :rot_auto
        assert zoom.auto_key == :zoom_auto
        assert_in_delta zoom.min, 1.0 / 11.0, 0.0001
        assert_in_delta zoom.max, 11.0, 0.0001
        assert sway.auto_key == :sway_auto
        assert rot_auto.companion_of == :rotate_scale
        refute Enum.any?(tweaks, &(&1.key == :orbit_rate))
        refute Enum.any?(tweaks, &(&1.key == :roll_rate))
      end)
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
          rotate_scale: 0.0,
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
          rotate_scale: 0.0,
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
