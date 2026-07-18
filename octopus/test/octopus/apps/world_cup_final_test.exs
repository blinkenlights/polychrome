defmodule Octopus.Apps.WorldCupFinalTest do
  use ExUnit.Case, async: true

  alias Octopus.Apps.WorldCupFinal
  alias Octopus.Canvas

  @app WorldCupFinal

  @default_config %{
    flag_a: :argentina,
    flag_b: :spain,
    hold_s: 12.0,
    crossfade_s: 0.6,
    dual_sided: true,
    floor: 8
  }

  @wide_config Map.put(@default_config, :dual_sided, false) |> Map.put(:floor, 0)

  setup do
    original_installation = Application.get_env(:octopus, :installation)

    on_exit(fn ->
      Application.put_env(:octopus, :installation, original_installation)
    end)

    :ok
  end

  test "list_modes/0 includes world cup final preset" do
    modes = world_cup_final_list_modes()
    mode = Enum.find(modes, &(&1.id == "worldcupfinal:world_cup_final"))
    assert mode.name == "World Cup Final"
    assert mode.builtin == true
  end

  test "mode_config/1 returns Argentina and Spain defaults" do
    assert world_cup_final_mode_config("worldcupfinal:world_cup_final") == @default_config
    assert world_cup_final_mode_config("world_cup_final") == @default_config
  end

  test "compatible?/0 on Woodstock 2x32" do
    Application.put_env(:octopus, :installation, Octopus.Installation.Woodstock)
    assert apply(@app, :compatible?, [])
  end

  test "compatible?/0 on wider installations" do
    Application.put_env(:octopus, :installation, Octopus.Installation.Woodstock1)
    assert apply(@app, :compatible?, [])
  end

  test "flag_color/2 for Argentina bands" do
    assert WorldCupFinal.flag_color(:argentina, 0.0) == {117, 170, 219}
    assert WorldCupFinal.flag_color(:argentina, 0.5) == {246, 180, 14}
    assert WorldCupFinal.flag_color(:argentina, 1.0) == {117, 170, 219}
  end

  test "flag_color/2 for France bands" do
    assert WorldCupFinal.flag_color(:france, 0.0) == {0, 85, 164}
    assert WorldCupFinal.flag_color(:france, 0.5) == {255, 255, 255}
    assert WorldCupFinal.flag_color(:france, 1.0) == {239, 65, 53}
  end

  test "flag_color/2 for England cross on a single column" do
    assert WorldCupFinal.flag_color(:england, 0.1) == {255, 255, 255}
    assert WorldCupFinal.flag_color(:england, 0.25) == {207, 19, 43}
    assert WorldCupFinal.flag_color(:england, 0.5) == {207, 19, 43}
    assert WorldCupFinal.flag_color(:england, 0.9) == {255, 255, 255}
  end

  test "flag_color/4 for England cross on a wide strip" do
    assert WorldCupFinal.flag_color(:england, 0.1, 0, 4) == {255, 255, 255}
    assert WorldCupFinal.flag_color(:england, 0.1, 3, 4) == {207, 19, 43}
    assert WorldCupFinal.flag_color(:england, 0.5, 0, 4) == {207, 19, 43}
  end

  test "visible_rows/2 leaves the bottom floor rows dark" do
    assert WorldCupFinal.visible_rows(32, 8) == 24
    assert WorldCupFinal.visible_rows(32, 0) == 32
  end

  test "dual-sided render mirrors each half of the canvas" do
    config = Map.put(@default_config, :floor, 0)
    canvas = WorldCupFinal.render_canvas(4, 24, 0.0, 0.0, config)

    for y <- 0..23 do
      assert Canvas.get_pixel(canvas, {0, y}) == Canvas.get_pixel(canvas, {2, y})
      assert Canvas.get_pixel(canvas, {1, y}) == Canvas.get_pixel(canvas, {3, y})
    end
  end

  test "dual-sided Woodstock render mirrors front and back columns" do
    canvas = WorldCupFinal.render_canvas(2, 24, 0.0, 0.0, Map.put(@default_config, :floor, 0))

    for y <- 0..23 do
      assert Canvas.get_pixel(canvas, {0, y}) == Canvas.get_pixel(canvas, {1, y})
    end
  end

  test "full-width render uses the entire canvas height" do
    canvas = WorldCupFinal.render_canvas(8, 32, 0.0, 0.0, @wide_config)

    assert map_size(canvas.pixels) == 8 * 32
  end

  test "flag_color/2 for Spain bands" do
    assert WorldCupFinal.flag_color(:spain, 0.0) == {170, 21, 27}
    assert WorldCupFinal.flag_color(:spain, 0.5) == {241, 191, 0}
    assert WorldCupFinal.flag_color(:spain, 1.0) == {170, 21, 27}
  end

  test "active_flag/2 alternates configured flags every hold period" do
    assert WorldCupFinal.active_flag(0.0, @default_config) == :argentina
    assert WorldCupFinal.active_flag(11.9, @default_config) == :argentina
    assert WorldCupFinal.active_flag(12.0, @default_config) == :spain
    assert WorldCupFinal.active_flag(23.9, @default_config) == :spain
    assert WorldCupFinal.active_flag(24.0, @default_config) == :argentina
  end

  test "flag_blend/2 crossfades between configured flags" do
    assert WorldCupFinal.flag_blend(0.0, @default_config) == {:argentina, 1.0}
    assert WorldCupFinal.flag_blend(12.0, @default_config) == {:spain, 1.0}

    assert match?(
             {:crossfade, :argentina, :spain, t} when t > 0.0 and t < 1.0,
             WorldCupFinal.flag_blend(11.7, @default_config)
           )
  end

  test "floor render only lights rows above the floor on a 2x32 canvas" do
    canvas = WorldCupFinal.render_canvas(2, 32, 0.0, 0.0, @default_config)

    assert map_size(canvas.pixels) == 2 * 24
    assert Enum.all?(Map.keys(canvas.pixels), fn {_x, y} -> y < 24 end)
  end

  test "render_canvas/5 produces flutter variation over anim time" do
    config = Map.put(@default_config, :floor, 0)
    still = WorldCupFinal.render_canvas(2, 24, 0.0, 0.0, config)
    later = WorldCupFinal.render_canvas(2, 24, 1.7, 0.0, config)

    refute Map.values(still.pixels) == Map.values(later.pixels)
  end

  test "flag_sample_u/3 oscillates around the flag center on narrow strips" do
    samples =
      for phase <- 0..24,
          do: WorldCupFinal.flag_sample_u(0, 1, phase / 3.0)

    assert Enum.all?(samples, fn u -> u >= 0.0 and u <= 1.0 end)
    assert length(Enum.uniq(samples)) > 1
    assert Enum.min(samples) < 0.5
    assert Enum.max(samples) > 0.5
  end

  test "horizontal sway shifts England cross emphasis over anim time" do
    config = Map.put(@default_config, :flag_a, :england) |> Map.put(:flag_b, :england)

    early = WorldCupFinal.render_canvas(2, 24, 0.0, 0.0, config)
    later = WorldCupFinal.render_canvas(2, 24, 4.2, 0.0, config)

    refute Map.values(early.pixels) == Map.values(later.pixels)
  end

  test "render_canvas/5 produces flag change over flag time" do
    config = Map.put(@default_config, :floor, 0)
    argentina = WorldCupFinal.render_canvas(2, 24, 0.0, 0.0, config)
    spain = WorldCupFinal.render_canvas(2, 24, 0.0, 12.0, config)

    refute Map.values(argentina.pixels) == Map.values(spain.pixels)
  end

  test "config_schema select defaults resolve to flag atoms" do
    defaults = Octopus.App.default_config(WorldCupFinal.config_schema())

    assert defaults.flag_a == :argentina
    assert defaults.flag_b == :spain
    assert defaults.dual_sided == false
    assert defaults.floor == 0
  end

  test "now_playing_meta/1 summarizes configured flags" do
    assert WorldCupFinal.now_playing_meta(@default_config) == [
             "Argentina",
             "Spain",
             "hold 12.0s",
             "dual-sided",
             "floor 8"
           ]
  end

  defp world_cup_final_list_modes, do: apply(@app, :list_modes, [])
  defp world_cup_final_mode_config(mode_id), do: apply(@app, :mode_config, [mode_id])
end
