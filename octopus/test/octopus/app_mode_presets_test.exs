defmodule Octopus.AppModePresetsTest do
  use Octopus.DataCase, async: true

  alias Octopus.AppModePresets
  alias Octopus.Apps.{Collective, Matrix, PixelFun, Sand, SparkleMist}

  setup do
    AppModePresets.sync_all!()
    :ok
  end

  describe "sync_builtins/1" do
    test "is idempotent and seeds all apps" do
      assert length(AppModePresets.list_presets(PixelFun)) == 7
      assert length(AppModePresets.list_presets(Collective)) == 6
      assert length(AppModePresets.list_presets(Matrix)) == 1
      assert length(AppModePresets.list_presets(Sand)) == 1
      assert length(AppModePresets.list_presets(SparkleMist)) == 1

      AppModePresets.sync_all!()

      assert length(AppModePresets.list_presets(PixelFun)) == 7
    end

    test "does not overwrite existing rows" do
      storm_id = AppModePresets.mode_id(Collective, "storm")

      assert {:ok, _} =
               AppModePresets.update(Collective, storm_id, %{
                 config: %{animation: :storm, background: :deep_dark, sensitivity: 9.0}
               })

      AppModePresets.sync_builtins(Collective)

      assert %{config: %{sensitivity: 9.0}} = AppModePresets.get(Collective, storm_id)
    end
  end

  describe "create/3 and archive/2" do
    test "creates user preset and archives it" do
      assert {:ok, preset} =
               AppModePresets.create(Collective, "My storm", %{
                 animation: :storm,
                 background: :deep_dark,
                 sensitivity: 1.5
               })

      assert preset.origin == :user
      assert String.starts_with?(preset.id, "collective:")

      assert :ok = AppModePresets.archive(Collective, preset.id)
      assert AppModePresets.get(Collective, preset.id) == nil
    end

    test "rejects invalid pixel fun formulas" do
      assert {:error, :invalid_formula} =
               AppModePresets.create(PixelFun, "Bad", %{program: "sin(+"})
    end
  end

  describe "rename/3 and update/3" do
    test "renames and overwrites builtins" do
      id = AppModePresets.mode_id(Matrix, "matrix")

      assert {:ok, renamed} = AppModePresets.rename(Matrix, id, "Code rain")
      assert renamed.name == "Code rain"

      assert {:ok, updated} =
               AppModePresets.update(Matrix, id, %{config: %{speed: 2.0, density: 4, max_particles: 100}})

      assert updated.config[:speed] == 2.0
    end
  end

  describe "normalize_mode_id/2" do
    test "maps legacy pixel fun and bare collective ids" do
      assert AppModePresets.normalize_mode_id(PixelFun, "builtin:classic_ripple") ==
               "pixelfun:classic_ripple"

      assert AppModePresets.normalize_mode_id(Collective, "storm") == "collective:storm"
      assert AppModePresets.normalize_mode_id(Matrix, "matrix") == "matrix:matrix"
      assert AppModePresets.normalize_mode_id(Sand, "sand") == "sand:sand"
      assert AppModePresets.normalize_mode_id(SparkleMist, "mist") == "sparklemist:mist"
    end
  end

  describe "list_modes/1" do
    test "returns foyer tiles with summaries" do
      modes = AppModePresets.list_modes(Collective)
      storm = Enum.find(modes, &(&1.id == "collective:storm"))

      assert storm.name == "Storm"
      assert storm.summary != ""
      assert storm.deletable
      assert storm.renamable
    end

    test "returns sand tiles with summaries" do
      [mode] = AppModePresets.list_modes(Sand)

      assert mode.id == "sand:sand"
      assert mode.summary != ""
      assert mode.deletable
      assert mode.renamable
    end

    test "returns sparkle mist tiles with summaries" do
      [mode] = AppModePresets.list_modes(SparkleMist)

      assert mode.id == "sparklemist:mist"
      assert mode.summary != ""
      assert mode.deletable
      assert mode.renamable
    end
  end

  describe "sparkle mist presets" do
    test "create, rename, and archive sparkle mist preset" do
      assert {:ok, preset} =
               AppModePresets.create(SparkleMist, "Violet haze", %{
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

      assert {:ok, renamed} = AppModePresets.rename(SparkleMist, preset.id, "Purple mist")
      assert renamed.name == "Purple mist"

      assert :ok = AppModePresets.archive(SparkleMist, preset.id)
      assert AppModePresets.get(SparkleMist, preset.id) == nil
    end
  end

  describe "sand presets" do
    test "create, rename, and archive sand preset" do
      assert {:ok, preset} =
               AppModePresets.create(Sand, "Heavy rain", %{
                 spawn_rate: 0.6,
                 button_force: 60,
                 auto_drain: true,
                 color_mode: :warm
               })

      assert preset.origin == :user
      assert preset.config[:spawn_rate] == 0.6

      assert {:ok, renamed} = AppModePresets.rename(Sand, preset.id, "Downpour")
      assert renamed.name == "Downpour"

      assert :ok = AppModePresets.archive(Sand, preset.id)
      assert AppModePresets.get(Sand, preset.id) == nil
    end
  end
end
