defmodule Octopus.Hardware.PanelTypeTest do
  use ExUnit.Case, async: true

  alias Octopus.Hardware.{PanelType, PanelTypes}

  describe "outer_dimensions_cm/1" do
    test "polychrome: 156 × 156 × 17 cm" do
      type = PanelTypes.fetch!(:polychrome)
      assert PanelType.outer_dimensions_cm(type) == {156.0, 156.0, 17.0}
    end

    test "pixie: 56 × 56 × 7 cm" do
      type = PanelTypes.fetch!(:pixie)
      assert PanelType.outer_dimensions_cm(type) == {56.0, 56.0, 7.0}
    end

    test "woodstock: 600 × 6 × 4 cm" do
      type = PanelTypes.fetch!(:woodstock)
      assert PanelType.outer_dimensions_cm(type) == {6.0, 600.0, 4.0}
    end
  end

  describe "pixel_aspect_ratio/1 and pixel_pitch_cm/1" do
    test "polychrome pitch includes gap" do
      type = PanelTypes.fetch!(:polychrome)
      assert_in_delta PanelType.pixel_aspect_ratio(type), 1.0, 0.001
      assert PanelType.pixel_pitch_cm(type) == {19.2875, 19.2875}
    end

    test "pixie square pixels" do
      type = PanelTypes.fetch!(:pixie)
      assert PanelType.pixel_aspect_ratio(type) == 1.0
      assert PanelType.pixel_pitch_cm(type) == {6.0, 6.0}
    end
  end
end
