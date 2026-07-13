defmodule Octopus.Installation.RadarConfigTest do
  use ExUnit.Case, async: true

  test "Nation2026 radar defaults store negative integers as literals" do
    defaults =
      Octopus.Installation.Nation2026.radar_config()
      |> Keyword.fetch!(:defaults)

    assert Keyword.fetch!(defaults, :x_neg_cm) == -500
    assert Keyword.fetch!(defaults, :y_neg_cm) == -500
    assert is_integer(Keyword.fetch!(defaults, :x_neg_cm))
    assert is_integer(Keyword.fetch!(defaults, :y_neg_cm))
  end
end
