defmodule Octopus.Params.GlobalTest do
  use ExUnit.Case, async: true

  alias Octopus.Params.Global

  describe "speed slider mapping" do
    test "round-trips endpoints" do
      assert Global.slider_to_speed(0) == Global.speed_min()
      assert Global.slider_to_speed(Global.speed_slider_steps()) == Global.speed_max()
    end

    test "maps 1.0 near the geometric midpoint" do
      slider = Global.speed_to_slider(1.0)
      assert_in_delta Global.slider_to_speed(slider), 1.0, 0.02
    end

    test "clamps out-of-range values" do
      assert Global.slider_to_speed(-10) == Global.speed_min()
      assert Global.slider_to_speed(9999) == Global.speed_max()
    end
  end
end
