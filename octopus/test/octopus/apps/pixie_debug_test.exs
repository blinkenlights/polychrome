defmodule Octopus.Apps.PixieDebugTest do
  use ExUnit.Case, async: false

  alias Octopus.Apps.PixieDebug.State
  alias Octopus.Canvas
  alias Octopus.Installation

  @pixie_debug Module.concat(["Octopus", "Apps", "PixieDebug"])

  setup do
    original_installation = Application.get_env(:octopus, :installation)

    on_exit(fn ->
      Application.put_env(:octopus, :installation, original_installation)
    end)

    %{original_installation: original_installation}
  end

  defp with_installation(installation, fun) do
    Application.put_env(:octopus, :installation, installation)
    fun.()
  end

  defp display_info do
    %{
      width: Installation.width(),
      height: Installation.height(),
      panel_width: Installation.panel_width(),
      panel_height: Installation.panel_height(),
      num_panels: Installation.num_panels(),
      panel_to_global_coords: fn panel_id, local_x, local_y ->
        if panel_id == 0, do: {local_x, local_y}, else: :invalid_panel
      end
    }
  end

  defp base_state(overrides) do
    defaults = %{
      mode_id: "pixel_walk",
      layout_index: 0,
      color_channel: :white,
      color: "#ffffff",
      display_info: display_info()
    }

    struct!(State, Map.merge(defaults, overrides))
  end

  test "compatible?/0 only on single 8x8 panel" do
    with_installation(Octopus.Installation.Pixie, fn ->
      assert pixie_compatible?()
    end)

    with_installation(Octopus.Installation.RunningLights, fn ->
      refute pixie_compatible?()
    end)
  end

  test "handle_config/2 updates layout_index" do
    with_installation(Octopus.Installation.Pixie, fn ->
      {:ok, app_id} =
        Octopus.AppSupervisor.start_app(@pixie_debug,
          config: %{mode_id: "pixel_walk", layout_index: 0}
        )

      :ok = Octopus.AppSupervisor.update_config(app_id, %{layout_index: 12})

      assert Octopus.AppSupervisor.config(app_id)[:layout_index] == 12
    end)
  end

  test "debug_info/1 returns wiring metadata on Pixie installation" do
    with_installation(Octopus.Installation.Pixie, fn ->
      info = pixie_debug_info(5)

      assert info.x == 5
      assert info.y == 0
      assert is_integer(info.strip)
      assert is_integer(info.firmware_index)
    end)
  end

  test "now_playing_meta/1 returns wiring lines for pixel walk" do
    with_installation(Octopus.Installation.Pixie, fn ->
      [line1, line2, line3] =
        pixie_now_playing_meta(%{mode_id: "pixel_walk", layout_index: 5})

      assert line1 =~ "Layout (5, 0)"
      assert line2 =~ "Strip position:"
      assert line3 =~ "Firmware buffer index:"
    end)
  end

  test "now_playing_meta/1 returns fill summary for full panel" do
    assert ["Panel fill · white"] ==
             pixie_now_playing_meta(%{
               mode_id: "full_panel",
               color_channel: :white
             })

    assert ["Panel fill · #ff00aa (RGB)"] ==
             pixie_now_playing_meta(%{
               mode_id: "full_panel",
               color_channel: :rgb,
               color: "#ff00aa"
             })
  end

  test "list_modes/0 exposes pixel_walk and full_panel" do
    mode_ids = pixie_list_modes() |> Enum.map(& &1.id)
    assert mode_ids == ["pixel_walk", "full_panel"]
    assert pixie_mode_tweakables("pixel_walk") != []
    assert pixie_mode_tweakables("full_panel") != []
  end

  test "full_panel white fills grayscale canvas" do
    with_installation(Octopus.Installation.Pixie, fn ->
      canvas = pixie_build_canvas(base_state(%{mode_id: "full_panel", color_channel: :white}))

      assert canvas.mode == :grayscale

      for y <- 0..(canvas.height - 1),
          x <- 0..(canvas.width - 1) do
        assert Canvas.get_pixel(canvas, {x, y}) == 255
      end
    end)
  end

  test "full_panel rgb fills canvas with chosen color" do
    with_installation(Octopus.Installation.Pixie, fn ->
      canvas =
        pixie_build_canvas(
          base_state(%{mode_id: "full_panel", color_channel: :rgb, color: "#ff0000"})
        )

      assert canvas.mode == :rgb
      assert Canvas.get_pixel(canvas, {0, 0}) == {255, 0, 0}
    end)
  end

  test "apply_mode/2 switches to full panel config" do
    with_installation(Octopus.Installation.Pixie, fn ->
      {:ok, app_id} =
        Octopus.AppSupervisor.start_app(@pixie_debug,
          config: %{mode_id: "pixel_walk", layout_index: 7}
        )

      :ok = pixie_apply_mode(app_id, "full_panel")

      config = Octopus.AppSupervisor.config(app_id)
      assert config[:mode_id] == "full_panel"
      assert config[:color_channel] == :white
      assert config[:color] == "#ffffff"
    end)
  end

  defp pixie_compatible?, do: apply(@pixie_debug, :compatible?, [])
  defp pixie_debug_info(index), do: apply(@pixie_debug, :debug_info, [index])
  defp pixie_now_playing_meta(config), do: apply(@pixie_debug, :now_playing_meta, [config])
  defp pixie_list_modes, do: apply(@pixie_debug, :list_modes, [])
  defp pixie_mode_tweakables(mode_id), do: apply(@pixie_debug, :mode_tweakables, [mode_id])
  defp pixie_build_canvas(state), do: apply(@pixie_debug, :build_canvas, [state])
  defp pixie_apply_mode(app_id, mode_id), do: apply(@pixie_debug, :apply_mode, [app_id, mode_id])
end
