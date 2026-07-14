defmodule Octopus.AppModePresetsTest do
  use Octopus.DataCase, async: true

  alias Octopus.Apps.{Collective, Fire, Matrix, PixelFun, Sand, SparkleMist, Wood}

  @presets Module.concat(["Octopus", "AppModePresets"])

  describe "loader/0" do
    test "embeds expected preset counts per app" do
      assert length(preset_list(PixelFun)) == 7
      assert length(preset_list(Collective)) == 8
      assert length(preset_list(Matrix)) == 1
      assert length(preset_list(Sand)) == 6
      assert length(preset_list(SparkleMist)) == 1
      assert length(preset_list(Wood)) == 2
      assert length(preset_list(Fire)) == 3
    end

    test "all presets are builtin origin" do
      for app <- [PixelFun, Collective, Matrix, Sand, SparkleMist, Wood, Fire],
          preset <- preset_list(app) do
        assert preset.origin == :builtin
      end
    end
  end

  describe "normalize_mode_id/2" do
    test "maps legacy pixel fun and bare collective ids" do
      assert preset_normalize_mode_id(PixelFun, "builtin:classic_ripple") ==
               "pixelfun:classic_ripple"

      assert preset_normalize_mode_id(Collective, "storm") == "collective:storm"
      assert preset_normalize_mode_id(Matrix, "matrix") == "matrix:matrix"
      assert preset_normalize_mode_id(Matrix, "matrix-ring") == "matrix:matrix"
      assert preset_normalize_mode_id(Sand, "sand") == "sand:sand"
      assert preset_normalize_mode_id(SparkleMist, "mist") == "sparklemist:mist"
      assert preset_normalize_mode_id(Wood, "experiment") == "wood:experiment"
      assert preset_normalize_mode_id(Fire, "campfire") == "fire:campfire"
      assert preset_normalize_mode_id(Fire, "default") == "fire:campfire"
    end
  end

  describe "list_modes/1" do
    test "returns foyer tiles with summaries" do
      modes = preset_list_modes(Collective)
      storm = Enum.find(modes, &(&1.id == "collective:storm"))

      assert storm.name == "Storm"
      assert storm.summary != ""
      refute storm.deletable
      refute storm.renamable
    end

    test "returns sand tiles with summaries" do
      modes = preset_list_modes(Sand)
      classic = Enum.find(modes, &(&1.id == "sand:sand"))
      storm = Enum.find(modes, &(&1.id == "sand:storm"))

      assert length(modes) == 6
      assert classic.summary != ""
      refute classic.deletable
      refute classic.renamable
      assert storm.summary =~ "wind auto"
    end

    test "returns sparkle mist tiles with summaries" do
      [mode] = preset_list_modes(SparkleMist)

      assert mode.id == "sparklemist:mist"
      assert mode.summary != ""
      refute mode.deletable
      refute mode.renamable
    end

    test "returns matrix tile with summary" do
      modes = preset_list_modes(Matrix)
      classic = Enum.find(modes, &(&1.id == "matrix:matrix"))

      assert classic.name == "matrix"
      assert classic.summary != ""
      refute Enum.any?(modes, &(&1.id == "matrix:matrix-ring"))
    end

    test "returns wood tiles with summaries" do
      modes = preset_list_modes(Wood)
      experiment = Enum.find(modes, &(&1.id == "wood:experiment"))
      mirror = Enum.find(modes, &(&1.id == "wood:mirror_strips"))

      assert experiment.name == "Experiment"
      assert experiment.summary != ""
      assert mirror.name == "Mirror strips"
      assert String.contains?(mirror.summary, "mirror")
    end

    test "returns fire tiles with summaries" do
      modes = preset_list_modes(Fire)
      campfire = Enum.find(modes, &(&1.id == "fire:campfire"))
      inferno = Enum.find(modes, &(&1.id == "fire:inferno"))

      assert length(modes) == 3
      assert campfire.name == "Campfire"
      assert campfire.summary != ""
      refute campfire.deletable
      refute campfire.renamable
      assert inferno.name == "Inferno"
    end
  end

  describe "get/2" do
    test "returns preset config from embedded JSON" do
      preset = preset_get(Matrix, "matrix:matrix")
      assert preset.origin == :builtin
      assert is_map(preset.config)
      assert preset.config[:speed] != nil
    end
  end

  defp preset_list(app), do: apply(@presets, :list_presets, [app])
  defp preset_list_modes(app), do: apply(@presets, :list_modes, [app])
  defp preset_normalize_mode_id(app, mode_id), do: apply(@presets, :normalize_mode_id, [app, mode_id])
  defp preset_get(app, mode_id), do: apply(@presets, :get, [app, mode_id])
end
