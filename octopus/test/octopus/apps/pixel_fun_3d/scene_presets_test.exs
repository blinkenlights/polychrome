defmodule Octopus.Apps.PixelFun3D.ScenePresetsTest do
  use Octopus.DataCase, async: false

  alias Octopus.Apps.PixelFun.Program
  alias Octopus.Apps.PixelFun3D.ScenePresets

  describe "builtins/0" do
    test "returns presets with valid formulas and scene fields" do
      presets = ScenePresets.builtins()

      assert length(presets) == 24

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
        kreiswelle chaser doppelhelix nordlicht wolkenzug seegras
        weiche_blobs leuchtplankton wasserwaage sternenhimmel nebeldrift
        facettenstrudel marmor
        strudel spiralband globus kippende_baender
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
      assert_in_delta facetten_config.rot_auto_range, 60.0, 0.0001
      assert_in_delta facetten_config.zoom_auto_range, 1.05, 0.0001

      globus_config = ScenePresets.to_config(ScenePresets.get("builtin:globus"))
      assert_in_delta globus_config.roll_rate, 6.0, 0.0001
      assert globus_config.roll_pivot == 0

      kipp_config = ScenePresets.to_config(ScenePresets.get("builtin:kippende_baender"))
      assert kipp_config.rot_auto == true
      assert_in_delta kipp_config.rot_auto_range, 45.0, 0.0001
      assert_in_delta kipp_config.rot_auto_interval, 60.0, 0.0001
    end

    test "config_matches? identifies each new builtin against its own config" do
      new_slugs = ~w(
        kreiswelle chaser doppelhelix nordlicht wolkenzug seegras
        weiche_blobs leuchtplankton wasserwaage sternenhimmel nebeldrift
        facettenstrudel marmor
        strudel spiralband globus kippende_baender
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
    test "returns embedded builtins only" do
      ids = ScenePresets.list_all() |> Enum.map(& &1.id)

      assert "builtin:classic_ripple" in ids
      assert length(ids) == 24
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

    test "round-trips auto keys from facettenstrudel builtin" do
      preset = ScenePresets.get("builtin:facettenstrudel")
      config = ScenePresets.to_config(preset)

      assert config.rot_auto == true
      assert config.zoom_auto == true
      assert is_number(config.rot_auto_range)
      assert ScenePresets.config_matches?(config, preset)
    end
  end

  describe "tilt preset round-trip" do
    test "wasserwaage builtin exposes tilt fields" do
      preset = ScenePresets.get("builtin:wasserwaage")

      assert preset.tilt_scale == 2.5
      assert preset.tilt_speed == 0.4
      assert preset.tilt_mode == :wobble
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

      assert summary =~ "trans auto"
      assert summary =~ "palette"
      assert summary =~ "sin"
    end

    test "renders sway mode for wasserwaage" do
      summary = ScenePresets.summary(ScenePresets.get("builtin:wasserwaage"))
      assert summary =~ "sway"
      assert summary =~ "wobble"
    end
  end

  describe "validate_formula/1" do
    test "accepts valid and rejects invalid input" do
      assert :ok = ScenePresets.validate_formula("sin(x+y+t)")
      assert :error = ScenePresets.validate_formula("(((")
    end
  end
end
