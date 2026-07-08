defmodule Octopus.Apps.PixelFun.ScenePresetsTest do
  use Octopus.DataCase, async: true

  alias Octopus.Apps.PixelFun.ScenePresets

  @scene_attrs %{
    name: "Test scene",
    formula: "sin(x+t)",
    color_interval: 5.0,
    translate_scale: 0.0,
    rotate_scale: 0.0,
    zoom_scale: 1.0
  }

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
    test "includes builtins and user presets" do
      assert {:ok, _} = ScenePresets.create(@scene_attrs)

      ids = ScenePresets.list_all() |> Enum.map(& &1.id)

      assert "builtin:classic_ripple" in ids
      assert Enum.any?(ids, &String.starts_with?(&1, "user:"))
    end
  end

  describe "get/1" do
    test "finds builtin and user presets" do
      assert %{name: "Classic ripple"} = ScenePresets.get("builtin:classic_ripple")

      {:ok, %{id: id}} = ScenePresets.create(@scene_attrs)

      assert ScenePresets.get(id) != nil
      assert ScenePresets.get("user:999999") == nil
    end
  end

  describe "create/1" do
    test "assigns random accent color when omitted" do
      assert {:ok, preset} = ScenePresets.create(@scene_attrs)
      assert Regex.match?(~r/^#[0-9A-F]{6}$/, preset.accent_color)
    end

    test "rejects invalid formulas" do
      assert {:error, changeset} =
               ScenePresets.create(Map.put(@scene_attrs, :formula, "sin(+"))

      assert "has invalid syntax" in errors_on(changeset).formula
    end

    test "rejects duplicate names" do
      assert {:ok, _} = ScenePresets.create(@scene_attrs)
      assert {:error, changeset} = ScenePresets.create(@scene_attrs)
      assert "has already been taken" in errors_on(changeset).name
    end
  end

  describe "update/2" do
    test "updates user presets but not builtins" do
      {:ok, %{id: id}} = ScenePresets.create(@scene_attrs)

      assert {:ok, updated} =
               ScenePresets.update(id, %{translate_scale: 2.0, rotate_scale: 0.5})

      assert updated.translate_scale == 2.0
      assert updated.rotate_scale == 0.5
      assert {:error, :builtin} = ScenePresets.update("builtin:cross_waves", %{name: "Nope"})
    end
  end

  describe "delete/1" do
    test "deletes user presets but not builtins" do
      {:ok, %{id: id}} = ScenePresets.create(@scene_attrs)

      assert :ok = ScenePresets.delete(id)
      assert ScenePresets.get(id) == nil
      assert {:error, :builtin} = ScenePresets.delete("builtin:cross_waves")
    end
  end

  describe "to_config/1 and config_matches?/2" do
    test "maps preset fields to app config" do
      preset = ScenePresets.get("builtin:classic_ripple")

      assert %{
               program: preset.formula,
               color_interval: preset.color_interval,
               translate_scale: preset.translate_scale,
               rotate_scale: preset.rotate_scale,
               zoom_scale: preset.zoom_scale
             } = ScenePresets.to_config(preset)
    end

    test "detects matching live config" do
      preset = ScenePresets.get("builtin:classic_ripple")
      config = ScenePresets.to_config(preset)

      assert ScenePresets.config_matches?(config, preset)
      refute ScenePresets.config_matches?(Map.put(config, :zoom_scale, 2.0), preset)
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
