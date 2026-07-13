defmodule Octopus.Radar.SensitivityTest do
  use ExUnit.Case, async: false

  alias Octopus.Radar.Sensitivity

  setup do
    start_supervised!(Sensitivity)
    :ok
  end

  test "defaults to the installation preset mapped to the UI scale" do
    assert Sensitivity.level() == 6
  end

  test "stores runtime level changes" do
    assert :ok = Sensitivity.set_level(1)
    assert Sensitivity.level() == 1

    assert :ok = Sensitivity.set_level(9)
    assert Sensitivity.level() == 9
  end
end
