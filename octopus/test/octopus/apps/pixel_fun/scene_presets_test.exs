defmodule Octopus.Apps.PixelFun.ScenePresetsTest do
  use Octopus.DataCase, async: false

  alias Octopus.Apps.PixelFun.ScenePresets

  describe "builtins/0" do
    test "returns presets with valid formulas and scene fields" do
      presets = ScenePresets.builtins()

      assert length(presets) == 7

      for preset <- presets do
        assert preset.builtin
        assert String.starts_with?(preset.id, "builtin:")
        assert Regex.match?(~r/^#[0-9A-F]{6}$/, preset.accent_color)
        assert ScenePresets.validate_formula(preset.formula) == :ok
      end
    end
  end

  describe "list_all/0" do
    test "returns embedded builtins only" do
      ids = ScenePresets.list_all() |> Enum.map(& &1.id)

      assert "builtin:classic_ripple" in ids
      assert length(ids) == 7
      refute Enum.any?(ids, &String.starts_with?(&1, "user:"))
    end
  end

  describe "get/1" do
    test "finds builtin presets" do
      assert %{name: "Classic ripple"} = ScenePresets.get("builtin:classic_ripple")
      assert ScenePresets.get("user:999999") == nil
    end
  end

  describe "to_config/1 and config_matches?/2" do
    test "maps preset fields to app config" do
      preset = ScenePresets.get("builtin:classic_ripple")

      assert ScenePresets.to_config(preset) == %{
               program: preset.formula,
               color_interval: preset.color_interval,
               translate_scale: preset.translate_scale,
               rotate_scale: preset.rotate_scale,
               zoom_scale: preset.zoom_scale,
               sway_scale: 0.0,
               sway_speed: 0.5,
               sway_mode: :wobble,
               time_direction: :forward
             }
    end

    test "detects matching live config" do
      preset = ScenePresets.get("builtin:classic_ripple")
      config = ScenePresets.to_config(preset)

      assert ScenePresets.config_matches?(config, preset)
      refute ScenePresets.config_matches?(Map.put(config, :zoom_scale, 2.0), preset)
    end

    test "treats missing sway keys as defaults" do
      preset = ScenePresets.get("builtin:classic_ripple")

      legacy_config = %{
        program: preset.formula,
        color_interval: preset.color_interval,
        translate_scale: preset.translate_scale,
        rotate_scale: preset.rotate_scale,
        zoom_scale: preset.zoom_scale
      }

      assert ScenePresets.config_matches?(legacy_config, preset)
    end
  end

  describe "id_for_config/1" do
    test "returns preset id or custom" do
      preset = ScenePresets.get("builtin:classic_ripple")
      config = ScenePresets.to_config(preset)

      assert preset.id == ScenePresets.id_for_config(config)
      assert "custom" == ScenePresets.id_for_config(Map.put(config, :program, "sin(x+t*99)"))
    end
  end

  describe "summary/1" do
    test "includes sliders and formula snippet" do
      preset = ScenePresets.get("builtin:classic_ripple")
      summary = ScenePresets.summary(preset)

      assert summary =~ "drift"
      assert summary =~ "palette"
      assert summary =~ "sin"
    end
  end

  describe "validate_formula/1" do
    test "accepts valid and rejects invalid input" do
      assert :ok = ScenePresets.validate_formula("sin(x+y+t)")
      assert :error = ScenePresets.validate_formula("(((")
    end
  end
end
