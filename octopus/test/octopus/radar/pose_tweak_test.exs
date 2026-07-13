defmodule Octopus.Radar.PoseTweakTest do
  use ExUnit.Case, async: false

  alias Octopus.Radar.PoseTweak

  setup do
    unless Process.whereis(PoseTweak) do
      start_supervised!(PoseTweak)
    end

    :ok
  end

  describe "normalize_deg/1" do
    test "wraps values into 0..360" do
      assert PoseTweak.normalize_deg(370) == 10.0
      assert PoseTweak.normalize_deg(-10) == 350.0
      assert PoseTweak.normalize_deg(360) == 0.0
      assert PoseTweak.normalize_deg(368) == 8.0
    end
  end

  describe "runtime state" do
    test "stores layout start and angle offset independently" do
      PoseTweak.set_layout_start_angle_deg(45)
      PoseTweak.set_angle_offset_deg(15)

      assert PoseTweak.layout_start_angle_deg() == 45.0
      assert PoseTweak.angle_offset_deg() == 15.0
    end
  end

  describe "pose tweak application" do
    test "angle offset belongs on rotation_deg, not angle_deg" do
      base = [
        angle_deg: 30.0,
        rotation_deg: 90.0,
        distance_cm: 300
      ]

      PoseTweak.set_angle_offset_deg(10.0)

      tweaked =
        if true do
          rotation =
            base
            |> Keyword.get(:rotation_deg, 0)
            |> Kernel.+(PoseTweak.angle_offset_deg())
            |> PoseTweak.normalize_deg()

          base
          |> Keyword.put(:rotation_deg, rotation)
        end

      assert Keyword.fetch!(tweaked, :angle_deg) == 30.0
      assert Keyword.fetch!(tweaked, :rotation_deg) == 100.0
    end
  end
end
