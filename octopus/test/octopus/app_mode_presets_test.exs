defmodule Octopus.AppModePresetsTest do
  use Octopus.DataCase, async: true

  alias Octopus.Apps.{Collective, Matrix, PixelFun, Sand, SparkleMist, Wood}

  @presets Module.concat(["Octopus", "AppModePresets"])

  setup do
    preset_sync_all!()
    :ok
  end

  describe "sync_builtins/1" do
    test "is idempotent and seeds all apps" do
      assert length(preset_list(PixelFun)) == 8
      assert length(preset_list(Collective)) == 6
      assert length(preset_list(Matrix)) == 2
      assert length(preset_list(Sand)) == 6
      assert length(preset_list(SparkleMist)) == 1
      assert length(preset_list(Wood)) == 2

      preset_sync_all!()

      assert length(preset_list(PixelFun)) == 8
    end

    test "does not overwrite existing rows" do
      storm_id = preset_mode_id(Collective, "storm")

      assert {:ok, _} =
               preset_update(Collective, storm_id, %{
                 config: %{animation: :storm, background: :deep_dark, sensitivity: 9.0}
               })

      preset_sync_builtins(Collective)

      assert %{config: %{sensitivity: 9.0}} = preset_get(Collective, storm_id)
    end
  end

  describe "create/3 and archive/2" do
    test "creates user preset and archives it" do
      assert {:ok, preset} =
               preset_create(Collective, "My storm", %{
                 animation: :storm,
                 background: :deep_dark,
                 sensitivity: 1.5
               })

      assert preset.origin == :user
      assert String.starts_with?(preset.id, "collective:")

      assert :ok = preset_archive(Collective, preset.id)
      assert preset_get(Collective, preset.id) == nil
    end

    test "rejects invalid pixel fun formulas" do
      assert {:error, :invalid_formula} =
               preset_create(PixelFun, "Bad", %{program: "sin(+"})
    end
  end

  describe "rename/3 and update/3" do
    test "renames and overwrites builtins" do
      id = preset_mode_id(Matrix, "matrix")

      assert {:ok, renamed} = preset_rename(Matrix, id, "Code rain")
      assert renamed.name == "Code rain"

      assert {:ok, updated} =
               preset_update(Matrix, id, %{config: %{speed: 2.0, density: 4, max_particles: 100}})

      assert updated.config[:speed] == 2.0
    end
  end

  describe "normalize_mode_id/2" do
    test "maps legacy pixel fun and bare collective ids" do
      assert preset_normalize_mode_id(PixelFun, "builtin:classic_ripple") ==
               "pixelfun:classic_ripple"

      assert preset_normalize_mode_id(Collective, "storm") == "collective:storm"
      assert preset_normalize_mode_id(Matrix, "matrix") == "matrix:matrix"
      assert preset_normalize_mode_id(Matrix, "matrix-ring") == "matrix:matrix-ring"
      assert preset_normalize_mode_id(Sand, "sand") == "sand:sand"
      assert preset_normalize_mode_id(SparkleMist, "mist") == "sparklemist:mist"
      assert preset_normalize_mode_id(Wood, "experiment") == "wood:experiment"
    end
  end

  describe "list_modes/1" do
    test "returns foyer tiles with summaries" do
      modes = preset_list_modes(Collective)
      storm = Enum.find(modes, &(&1.id == "collective:storm"))

      assert storm.name == "Storm"
      assert storm.summary != ""
      assert storm.deletable
      assert storm.renamable
    end

    test "returns sand tiles with summaries" do
      modes = preset_list_modes(Sand)
      classic = Enum.find(modes, &(&1.id == "sand:sand"))
      storm = Enum.find(modes, &(&1.id == "sand:storm"))

      assert length(modes) == 6
      assert classic.summary != ""
      assert classic.deletable
      assert classic.renamable
      assert storm.summary =~ "wind auto"
    end

    test "returns sparkle mist tiles with summaries" do
      [mode] = preset_list_modes(SparkleMist)

      assert mode.id == "sparklemist:mist"
      assert mode.summary != ""
      assert mode.deletable
      assert mode.renamable
    end

    test "returns matrix tiles with summaries" do
      modes = preset_list_modes(Matrix)
      classic = Enum.find(modes, &(&1.id == "matrix:matrix"))
      ring = Enum.find(modes, &(&1.id == "matrix:matrix-ring"))

      assert classic.name == "matrix"
      assert classic.summary != ""
      assert ring.name == "matrix ring"
      assert String.contains?(ring.summary, "ring")
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
  end

  describe "sparkle mist presets" do
    test "create, rename, and archive sparkle mist preset" do
      assert {:ok, preset} =
               preset_create(SparkleMist, "Violet haze", %{
                 foreground_hue: 280,
                 background_hue_a: 220,
                 background_hue_b: 190,
                 background_sat_a: 100,
                 background_sat_b: 85,
                 expr: "noise(sin(x/26-t+y/40),x*0.01,y*0.01)",
                 particle_speed_scale: 1.5,
                 background_speed: 4.0
               })

      assert preset.origin == :user
      assert preset.config[:foreground_hue] == 280

      assert {:ok, renamed} = preset_rename(SparkleMist, preset.id, "Purple mist")
      assert renamed.name == "Purple mist"

      assert :ok = preset_archive(SparkleMist, preset.id)
      assert preset_get(SparkleMist, preset.id) == nil
    end
  end

  describe "sand presets" do
    test "create, rename, and archive sand preset" do
      assert {:ok, preset} =
               preset_create(Sand, "Heavy rain", %{
                 spawn_rate: 0.6,
                 button_force: 60,
                 auto_drain: true,
                 color_mode: :warm
               })

      assert preset.origin == :user
      assert preset.config[:spawn_rate] == 0.6

      assert {:ok, renamed} = preset_rename(Sand, preset.id, "Downpour")
      assert renamed.name == "Downpour"

      assert :ok = preset_archive(Sand, preset.id)
      assert preset_get(Sand, preset.id) == nil
    end
  end

  defp preset_sync_all!, do: apply(@presets, :sync_all!, [])
  defp preset_sync_builtins(app), do: apply(@presets, :sync_builtins, [app])
  defp preset_list(app), do: apply(@presets, :list_presets, [app])
  defp preset_list_modes(app), do: apply(@presets, :list_modes, [app])
  defp preset_mode_id(app, slug), do: apply(@presets, :mode_id, [app, slug])
  defp preset_normalize_mode_id(app, mode_id), do: apply(@presets, :normalize_mode_id, [app, mode_id])
  defp preset_get(app, mode_id), do: apply(@presets, :get, [app, mode_id])
  defp preset_create(app, name, config), do: apply(@presets, :create, [app, name, config])
  defp preset_update(app, mode_id, attrs), do: apply(@presets, :update, [app, mode_id, attrs])
  defp preset_rename(app, mode_id, name), do: apply(@presets, :rename, [app, mode_id, name])
  defp preset_archive(app, mode_id), do: apply(@presets, :archive, [app, mode_id])
end
