defmodule Octopus.Apps.WoodTest do
  use ExUnit.Case, async: false

  alias Octopus.Apps.Wood.State
  alias Octopus.Canvas
  alias Octopus.Installation

  @wood Module.concat(["Octopus", "Apps", "Wood"])

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
    num_panels = Installation.num_panels()
    panel_width = Installation.panel_width()
    panel_height = Installation.panel_height()
    panel_gap = Installation.panel_gap()

    panel_to_global_coords = fn panel_id, local_x, local_y ->
      if panel_id >= 0 and panel_id < num_panels do
        x_offset = panel_id * (panel_width + panel_gap)
        {x_offset + local_x, local_y}
      else
        :invalid_panel
      end
    end

    %{
      width: Installation.width(),
      height: Installation.height(),
      panel_width: panel_width,
      panel_height: panel_height,
      num_panels: num_panels,
      panel_to_global_coords: panel_to_global_coords
    }
  end

  defp base_state(overrides \\ %{}) do
    defaults = %{
      display_info: display_info(),
      position: 0.0,
      velocity: 0.0,
      direction: 1.0,
      global_speed: 1.0,
      blob_size: 1,
      blob_count: 1,
      blob_spacing: 1,
      mode: :endless_up,
      bounce: false,
      speed: 0.0,
      color_channel: :white,
      rgb_mode: :static,
      color: "#78c850",
      hue_cycle_speed: 30.0,
      cycle_phase: 0.0,
      trail_length: 0
    }

    struct!(State, Map.merge(defaults, overrides))
  end

  defp lit_grayscale_pixels(canvas) do
    for y <- 0..(canvas.height - 1),
        x <- 0..(canvas.width - 1),
        Canvas.get_pixel(canvas, {x, y}) > 0,
        do: {x, y}
  end

  defp lit_ys(canvas) do
    canvas |> lit_grayscale_pixels() |> Enum.map(fn {_, y} -> y end) |> Enum.sort()
  end

  test "compatible?/0 for Running Lights vertical strip", _context do
    with_installation(Octopus.Installation.RunningLights, fn ->
      assert wood_compatible?()
    end)
  end

  test "compatible?/0 for Woodstock 2x32 panels", _context do
    with_installation(Octopus.Installation.Woodstock2, fn ->
      assert wood_compatible?()
    end)
  end

  test "compatible?/0 for Woodstock 1x32 panels", _context do
    with_installation(Octopus.Installation.Woodstock1, fn ->
      assert wood_compatible?()
    end)
  end

  test "build_canvas/1 accepts db-style string enums", _context do
    with_installation(Octopus.Installation.Woodstock1, fn ->
      config =
        apply(@wood, :normalize_mode_config, [
          %{mode: "endless_up", color_channel: "white", speed: 2.0, blob_size: 3}
        ])

      canvas = wood_build_canvas(struct!(base_state(), config))

      assert canvas.mode == :grayscale
      assert length(lit_grayscale_pixels(canvas)) > 0
    end)
  end

  test "mode_config/1 merges legacy defaults with stored db config", _context do
    config = apply(@wood, :mode_config, ["wood:experiment"])

    assert config[:mode] == :endless_up
    assert config[:color_channel] == :white
    assert config[:speed] == 2.0
    assert config[:blob_size] == 3
  end

  test "build_canvas/1 lights bottom pixel on all Woodstock2 panels", _context do
    with_installation(Octopus.Installation.Woodstock2, fn ->
      canvas = wood_build_canvas(base_state())

      assert canvas.mode == :grayscale
      assert {canvas.width, canvas.height} == {36, 32}
      assert Enum.sort(lit_grayscale_pixels(canvas)) == [{0, 31}, {34, 31}]
    end)
  end

  test "build_canvas/1 lights bottom pixel on all Woodstock1 panels", _context do
    with_installation(Octopus.Installation.Woodstock1, fn ->
      canvas = wood_build_canvas(base_state())

      assert canvas.mode == :grayscale
      assert {canvas.width, canvas.height} == {34, 32}
      assert Enum.sort(lit_grayscale_pixels(canvas)) == [{0, 31}, {33, 31}]
    end)
  end

  test "build_canvas/1 lights bottom pixel when static at position 0", _context do
    with_installation(Octopus.Installation.RunningLights, fn ->
      canvas = wood_build_canvas(base_state())

      assert canvas.mode == :grayscale
      assert {canvas.width, canvas.height} == {1, 24}
      assert lit_grayscale_pixels(canvas) == [{0, 23}]
    end)
  end

  test "build_canvas/1 fullcolor fills entire strip white", _context do
    with_installation(Octopus.Installation.RunningLights, fn ->
      canvas = wood_build_canvas(base_state(%{mode: :fullcolor, color_channel: :white}))

      assert canvas.mode == :grayscale
      assert length(lit_grayscale_pixels(canvas)) == 24
    end)
  end

  test "build_canvas/1 fullcolor fills entire strip with rgb color", _context do
    with_installation(Octopus.Installation.RunningLights, fn ->
      canvas =
        wood_build_canvas(base_state(%{mode: :fullcolor, color_channel: :rgb, color: "#ff0000"}))

      assert canvas.mode == :rgb
      assert Canvas.get_pixel(canvas, {0, 0}) == {255, 0, 0}
      assert Canvas.get_pixel(canvas, {0, 23}) == {255, 0, 0}
    end)
  end

  test "build_canvas/1 chains multiple blobs in endless mode", _context do
    with_installation(Octopus.Installation.RunningLights, fn ->
      canvas =
        wood_build_canvas(
          base_state(%{
            mode: :endless_up,
            blob_count: 2,
            blob_size: 1,
            blob_spacing: 2,
            position: 0.0
          })
        )

      assert Enum.sort(lit_grayscale_pixels(canvas)) == [{0, 20}, {0, 23}]
    end)
  end

  test "build_canvas/1 chains blobs only in up and down mode", _context do
    with_installation(Octopus.Installation.RunningLights, fn ->
      canvas =
        wood_build_canvas(
          base_state(%{
            mode: :up_and_down,
            blob_count: 2,
            blob_size: 1,
            blob_spacing: 2,
            position: 0.0
          })
        )

      assert Enum.sort(lit_grayscale_pixels(canvas)) == [{0, 20}, {0, 23}]
    end)
  end

  test "build_canvas/1 wraps blob pixels seamlessly at strip edge", _context do
    with_installation(Octopus.Installation.RunningLights, fn ->
      canvas =
        wood_build_canvas(
          base_state(%{
            mode: :endless_up,
            blob_size: 3,
            position: 23.0
          })
        )

      assert lit_ys(canvas) == [0, 1, 23]
    end)
  end

  test "build_canvas/1 wraps trail seamlessly at strip edge", _context do
    with_installation(Octopus.Installation.RunningLights, fn ->
      canvas =
        wood_build_canvas(
          base_state(%{
            mode: :endless_up,
            position: 1.0,
            direction: 1.0,
            speed: 1.0,
            trail_length: 2
          })
        )

      assert lit_ys(canvas) == [0, 22, 23]
    end)
  end

  test "build_canvas/1 uses rgb for rgb channel with picked color", _context do
    with_installation(Octopus.Installation.RunningLights, fn ->
      canvas = wood_build_canvas(base_state(%{color_channel: :rgb, color: "#ff0000"}))

      assert canvas.mode == :rgb
      assert Canvas.get_pixel(canvas, {0, 23}) == {255, 0, 0}
    end)
  end

  test "wrap_coord/2 loops across strip length", _context do
    assert wood_wrap_coord(24.0, 24) == 0.0
    assert wood_wrap_coord(-0.5, 24) == 23.5
  end

  test "loop_step/3 keeps moving upward through wrap", _context do
    state = base_state(%{mode: :endless_up, speed: 1.0})
    {pos, _v, dir} = wood_loop_step(state, 1.0, 24, :endless_up)
    assert pos == 1.0
    assert dir == 1.0

    state = %{state | position: 23.5}
    {pos, _v, _dir} = wood_loop_step(state, 1.0, 24, :endless_up)
    assert pos == 0.5
  end

  test "loop_step/3 keeps moving downward through wrap", _context do
    state = base_state(%{mode: :endless_down, position: 0.2, speed: 1.0})
    {pos, _v, dir} = wood_loop_step(state, 0.5, 24, :endless_down)
    assert pos == 23.7
    assert dir == -1.0
  end

  test "ping_pong_step/3 reflects at ends", _context do
    state = base_state(%{mode: :up_and_down, position: 22.8, direction: 1.0, speed: 2.0})
    {pos, _velocity, direction} = wood_ping_pong_step(state, 1.0, 23)
    assert pos < 23.0
    assert direction == -1.0
  end

  defp wood_compatible?, do: apply(@wood, :compatible?, [])
  defp wood_build_canvas(state), do: apply(@wood, :build_canvas, [state])
  defp wood_wrap_coord(coord, length), do: apply(@wood, :wrap_coord, [coord, length])
  defp wood_loop_step(state, dt, length, mode), do: apply(@wood, :loop_step, [state, dt, length, mode])
  defp wood_ping_pong_step(state, dt, max_pos), do: apply(@wood, :ping_pong_step, [state, dt, max_pos])
end
