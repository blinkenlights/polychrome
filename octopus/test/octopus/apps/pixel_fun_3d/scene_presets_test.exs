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
    zoom_base: 1.0
  }

  describe "builtins/0" do
    test "returns presets with valid formulas and scene fields" do
      presets = ScenePresets.builtins()

      assert length(presets) == 27

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

    test "new builtin formulas evaluate to finite floats" do
      samples = [
        %{x: 0.0, y: 0.0, i: 0.0, nx: 1.0, ny: 0.0, nz: 0.0},
        %{x: 78.0, y: 1.5, i: 5.0, nx: 0.0, ny: 1.0, nz: 0.0},
        %{x: -50.0, y: -2.0, i: 11.0, nx: 0.3, ny: -0.4, nz: 0.866},
        # acos/atan2 edge cases: antipode of panel 0 and both poles
        %{x: 0.0, y: 0.0, i: 0.0, nx: -1.0, ny: 0.0, nz: 0.0},
        %{x: 0.0, y: 0.0, i: 0.0, nx: 0.0, ny: 0.0, nz: 1.0},
        %{x: 0.0, y: 0.0, i: 0.0, nx: 0.0, ny: 0.0, nz: -1.0}
      ]

      new_slugs = ~w(
        kreiswelle chaser doppelhelix nordlicht wolkenzug seegras quallenpuls
        weiche_blobs leuchtplankton wasserwaage sternenhimmel nebeldrift
        facettenstrudel marmor
        strudel spiralband globus polarlicht_parade kippende_baender
      )

      for slug <- new_slugs do
        preset = ScenePresets.get("builtin:#{slug}")
        assert preset != nil, "missing builtin #{slug}"
        assert {:ok, program} = Program.parse(preset.formula)

        for %{x: x, y: y, i: i, nx: nx, ny: ny, nz: nz} <- samples,
            t <- [0.0, 1.0, 10.0] do
          env = [
            %{
              ~c"x" => x,
              ~c"y" => y,
              ~c"t" => t,
              ~c"i" => i,
              ~c"nx" => nx,
              ~c"ny" => ny,
              ~c"nz" => nz,
              ~c"pi" => :math.pi(),
              ~c"PI" => :math.pi(),
              ~c"tau" => 2 * :math.pi()
            }
          ]

          value = Program.eval(program, env)
          assert is_float(value) or is_integer(value)
          assert value == value
          assert abs(value) <= 2.5
        end
      end
    end

    test "recipe builtins apply transform config" do
      wasserwaage = ScenePresets.get("builtin:wasserwaage")
      wasser_config = ScenePresets.to_config(wasserwaage)

      assert_in_delta wasser_config.tilt_scale, 2.5, 0.0001
      assert_in_delta wasser_config.tilt_speed, 0.4, 0.0001
      assert wasser_config.tilt_mode == :wobble

      facetten = ScenePresets.get("builtin:facettenstrudel")
      facetten_config = ScenePresets.to_config(facetten)

      assert facetten_config.rot_auto == true
      assert facetten_config.zoom_auto == true
      assert_in_delta facetten_config.rot_auto_range, 30.0, 0.0001
      assert_in_delta facetten_config.zoom_auto_range, 1.4, 0.0001

      globus_config = ScenePresets.to_config(ScenePresets.get("builtin:globus"))
      assert_in_delta globus_config.roll_rate, 6.0, 0.0001
      assert globus_config.roll_pivot == 0

      polar_config = ScenePresets.to_config(ScenePresets.get("builtin:polarlicht_parade"))
      assert_in_delta polar_config.roll_rate, 4.0, 0.0001
      assert polar_config.roll_pivot == 6

      kipp_config = ScenePresets.to_config(ScenePresets.get("builtin:kippende_baender"))
      assert kipp_config.rot_auto == true
      assert_in_delta kipp_config.rot_auto_range, 20.0, 0.0001
      assert_in_delta kipp_config.rot_auto_interval, 40.0, 0.0001
    end

    test "config_matches? identifies each new builtin against its own config" do
      new_slugs = ~w(
        kreiswelle chaser doppelhelix nordlicht wolkenzug seegras quallenpuls
        weiche_blobs leuchtplankton wasserwaage sternenhimmel nebeldrift
        facettenstrudel marmor
        strudel spiralband globus polarlicht_parade kippende_baender
      )

      for slug <- new_slugs do
        preset = ScenePresets.get("builtin:#{slug}")
        config = ScenePresets.to_config(preset)

        assert ScenePresets.config_matches?(config, preset),
               "#{slug} should match its own config"
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

    test "renders sway mode for wasserwaage" do
      summary = ScenePresets.summary(ScenePresets.get("builtin:wasserwaage"))
      assert summary =~ "sway 2.5px wobble"
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
