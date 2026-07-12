defmodule Octopus.Apps.PixelFun3D.ScenePresetsTest do
  use Octopus.DataCase, async: false

  alias Octopus.Apps.PixelFun.Program
  alias Octopus.Apps.PixelFun3D.ScenePresets

  @presets Module.concat(["Octopus", "AppModePresets"])

  setup do
    preset_sync_all!()
    :ok
  end

  @scene_attrs %{
    name: "Test scene",
    formula: "sin(x+t)",
    color_interval: 5.0,
    orbit_rate: 0.0,
    roll_rate: 0.0,
    zoom_base: 0.0
  }

  describe "builtins/0" do
    test "returns presets with valid formulas and scene fields" do
      presets = ScenePresets.builtins()

      assert length(presets) == 8

      for preset <- presets do
        assert preset.builtin
        assert String.starts_with?(preset.id, "builtin:")
        assert Regex.match?(~r/^#[0-9A-F]{6}$/, preset.accent_color)
        assert ScenePresets.validate_formula(preset.formula) == :ok
      end
    end

    test "normalized formulas parse via Program.parse" do
      for preset <- ScenePresets.builtins() do
        assert {:ok, _} = Program.parse(preset.formula)
      end
    end
  end

  describe "list_all/0" do
    test "includes builtins and user presets" do
      assert {:ok, _} = ScenePresets.create(@scene_attrs)

      ids = ScenePresets.list_all() |> Enum.map(& &1.id)

      assert "builtin:classic_ripple" in ids
      assert Enum.any?(ids, fn id ->
               String.starts_with?(id, "user:") or String.starts_with?(id, "pixelfun3d:")
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
               ScenePresets.update(id, %{orbit_rate: 2.0, roll_rate: 0.5})

      assert updated.orbit_rate == 2.0
      assert updated.roll_rate == 0.5

      assert {:ok, builtin} =
               ScenePresets.update("builtin:cross_waves", %{orbit_rate: 3.0})

      assert builtin.orbit_rate == 3.0
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
      config = ScenePresets.to_config(preset)

      assert config.program == preset.formula
      assert config.color_interval == preset.color_interval
      assert config.orbit_rate == 0.0
      assert config.roll_rate == 0.0
      assert config.tilt_scale == 0.0
      assert config.time_direction == :forward
    end

    test "detects matching live config" do
      preset = ScenePresets.get("builtin:classic_ripple")
      config = ScenePresets.to_config(preset)

      assert ScenePresets.config_matches?(config, preset)
      refute ScenePresets.config_matches?(Map.put(config, :zoom_base, 2.0), preset)
    end

    test "treats legacy keys as migrated equivalents" do
      preset = ScenePresets.get("builtin:classic_ripple")

      legacy_config = %{
        program: preset.formula,
        color_interval: preset.color_interval,
        translate_scale: 0.0,
        rotate_scale: 0.0,
        zoom_scale: 0.0,
        sway_scale: 0.0,
        sway_speed: 0.5,
        sway_mode: :wobble
      }

      assert ScenePresets.config_matches?(legacy_config, legacy_config)
      assert ScenePresets.config_matches?(ScenePresets.to_config(preset), preset)
    end

    test "round-trips auto keys and pattern_speed" do
      attrs =
        Map.merge(@scene_attrs, %{
          name: "Auto roundtrip",
          trans_auto: true,
          trans_auto_range_x: 1.2,
          trans_auto_range_y: 1.5,
          trans_auto_interval: 30.0,
          rot_auto: false,
          zoom_auto: true,
          zoom_auto_range: 1.5,
          zoom_auto_interval: 17.0,
          sway_auto: true,
          sway_auto_range: 1.1,
          sway_auto_interval: 22.0,
          pattern_speed: 1.25,
          pixel_fun_units: 2
        })

      assert {:ok, preset} = ScenePresets.create(attrs)
      config = ScenePresets.to_config(preset)

      assert config.trans_auto == true
      assert_in_delta config.trans_auto_range_x, 1.2, 0.0001
      assert_in_delta config.trans_auto_interval, 30.0, 0.0001
      assert config.zoom_auto == true
      assert config.sway_auto == true
      assert_in_delta config.pattern_speed, 1.25, 0.0001
      assert ScenePresets.config_matches?(config, preset)
    end
  end

  describe "tilt preset round-trip" do
    test "create and update persist tilt fields; legacy sway migrates" do
      attrs =
        Map.merge(@scene_attrs, %{
          sway_scale: 1.5,
          sway_speed: 0.8,
          sway_mode: :pendulum
        })

      assert {:ok, created} = ScenePresets.create(attrs)
      assert created.tilt_scale == 1.5
      assert created.tilt_speed == 0.8
      assert created.tilt_mode == :pendulum

      assert {:ok, updated} =
               ScenePresets.update(created.id, %{tilt_scale: 2.0, tilt_mode: :wobble})

      assert updated.tilt_scale == 2.0
      assert updated.tilt_mode == :wobble
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

      assert summary =~ "tx"
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
