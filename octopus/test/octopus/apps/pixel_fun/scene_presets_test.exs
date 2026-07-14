defmodule Octopus.Apps.PixelFun.ScenePresetsTest do
  use Octopus.DataCase, async: false

  alias Octopus.Apps.PixelFun.ScenePresets

  @presets Module.concat(["Octopus", "AppModePresets"])

  setup do
    preset_sync_all!()
    :ok
  end

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
      assert Enum.any?(ids, fn id ->
               String.starts_with?(id, "user:") or String.starts_with?(id, "pixelfun:")
             end)
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

    test "allows duplicate names with distinct slugs" do
      assert {:ok, first} = ScenePresets.create(@scene_attrs)
      assert {:ok, second} = ScenePresets.create(@scene_attrs)
      assert first.id != second.id
    end
  end

  describe "update/2" do
    test "updates user presets and builtins" do
      {:ok, %{id: id}} = ScenePresets.create(@scene_attrs)

      assert {:ok, updated} =
               ScenePresets.update(id, %{translate_scale: 2.0, rotate_scale: 0.5})

      assert updated.translate_scale == 2.0
      assert updated.rotate_scale == 0.5

      assert {:ok, builtin} =
               ScenePresets.update("builtin:cross_waves", %{translate_scale: 3.0})

      assert builtin.translate_scale == 3.0
    end
  end

  describe "delete/1" do
    test "archives user presets and builtins" do
      {:ok, %{id: id}} = ScenePresets.create(@scene_attrs)

      assert :ok = ScenePresets.delete(id)
      assert ScenePresets.get(id) == nil

      assert :ok = ScenePresets.delete("builtin:cross_waves")
      assert ScenePresets.get("builtin:cross_waves") == nil
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

  describe "sway preset round-trip" do
    test "create and update persist sway fields" do
      attrs =
        Map.merge(@scene_attrs, %{
          sway_scale: 1.5,
          sway_speed: 0.8,
          sway_mode: :pendulum
        })

      assert {:ok, created} = ScenePresets.create(attrs)
      assert created.sway_scale == 1.5
      assert created.sway_speed == 0.8
      assert created.sway_mode == :pendulum

      assert {:ok, updated} =
               ScenePresets.update(created.id, %{sway_scale: 2.0, sway_mode: :wobble})

      assert updated.sway_scale == 2.0
      assert updated.sway_mode == :wobble
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

  defp preset_sync_all!, do: apply(@presets, :sync_all!, [])
end
