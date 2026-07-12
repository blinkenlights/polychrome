defmodule Octopus.MixerTest do
  use ExUnit.Case, async: false
  alias Octopus.{Mixer, Canvas}

  setup do
    # Start the mixer if not already started
    case GenServer.whereis(Mixer) do
      nil -> start_supervised!(Mixer)
      _pid -> :ok
    end

    :ok
  end

  test "display info contains expected fields" do
    display_info = Mixer.get_display_info()

    assert is_integer(display_info.width)
    assert is_integer(display_info.height)
    assert is_integer(display_info.panel_width)
    assert is_integer(display_info.panel_height)
    assert is_integer(display_info.num_panels)
    assert is_integer(display_info.panel_gap)
    assert is_function(display_info.panel_range, 2)
    assert is_function(display_info.panel_at_coord, 2)
  end

  test "can create display buffers for an app" do
    app_id = :test_app
    config = %{supports_rgb: true, supports_grayscale: false}

    assert :ok = Mixer.create_display_buffers(app_id, config)
  end

  test "can update app display" do
    app_id = :test_app_2
    config = %{supports_rgb: true, supports_grayscale: false}

    # Create buffers first
    Mixer.create_display_buffers(app_id, config)

    # Create a test canvas
    canvas = Canvas.new(10, 8) |> Canvas.put_pixel({0, 0}, {255, 0, 0})

    # Update should not crash
    assert :ok = Mixer.update_app_display(app_id, canvas, :rgb)
  end

  test "panel_range function works correctly" do
    display_info = Mixer.get_display_info()

    # Test first panel x range
    {start_x, end_x} = display_info.panel_range.(0, :x)
    assert start_x == 0
    assert end_x == display_info.panel_width - 1

    # Test first panel y range
    {start_y, end_y} = display_info.panel_range.(0, :y)
    assert start_y == 0
    assert end_y == display_info.panel_height - 1
  end

  test "panel_at_coord function works correctly" do
    display_info = Mixer.get_display_info()

    # First panel should contain coordinate (0, 0)
    assert display_info.panel_at_coord.(0, 0) == 0

    # Outside bounds should return :not_found
    assert display_info.panel_at_coord.(-1, 0) == :not_found
    assert display_info.panel_at_coord.(0, -1) == :not_found
  end

  test "panel_to_global_coords uses range start for y" do
    display_info = Mixer.get_display_info()

    assert display_info.panel_to_global_coords.(0, 0, 0) == {0, 0}

    assert display_info.panel_to_global_coords.(0, display_info.panel_width - 1, 0) ==
             {display_info.panel_width - 1, 0}

    assert display_info.panel_to_global_coords.(0, 0, display_info.panel_height - 1) ==
             {0, display_info.panel_height - 1}
  end

  test "idle frame does not crash when no app is selected" do
    send(Mixer, :idle_frame)
    _ = :sys.get_state(Mixer)
  end

  test "uses cached bleeding config when rendering frames" do
    app_id = "bleedapp"

    config = %{
      supports_rgb: true,
      supports_grayscale: false,
      bleeding: 42.0,
      merge_rgbw: false
    }

    Mixer.create_display_buffers(app_id, config)

    :sys.replace_state(Mixer, fn state ->
      %{state | rendered_app: app_id}
    end)

    canvas = Canvas.new(10, 8) |> Canvas.put_pixel({0, 0}, {255, 0, 0})

    assert :ok = Mixer.update_app_display(app_id, canvas, :rgb)
    _ = :sys.get_state(Mixer)
  end

  test "config_updated merges bleeding without replacing display metadata" do
    app_id = "metadatapp"

    display_config = %{
      layout: :gapped_panels,
      supports_rgb: true,
      supports_grayscale: true,
      merge_rgbw: true,
      easing_interval: 200,
      bleeding: 0.0
    }

    Mixer.create_display_buffers(app_id, display_config)

    runtime_config = %{program: "sin(x)", bleeding: 55.0}
    send(Mixer, {:apps, {:config_updated, app_id, runtime_config}})
    _ = :sys.get_state(Mixer)

    app_display = :sys.get_state(Mixer).app_displays |> Map.fetch!(app_id)

    assert app_display.config.layout == :gapped_panels
    assert app_display.config.supports_grayscale == true
    assert app_display.config.merge_rgbw == true
    assert app_display.config.easing_interval == 200
    assert app_display.config.bleeding == 55.0
  end

  test "retargets in-flight fade-out when a new app is selected during stop-then-start" do
    old_app = "oldapp1"
    new_app = "newapp1"

    :sys.replace_state(Mixer, fn state ->
      %{state | rendered_app: old_app, transition: {:out, 200, nil}}
    end)

    send(Mixer, {:app_manager, {:selected_app, new_app}})

    state = :sys.get_state(Mixer)
    assert state.transition == {:out, 200, new_app}
    assert state.rendered_app == old_app

    :sys.replace_state(Mixer, fn state ->
      %{state | transition: {:out, 0, new_app}}
    end)

    send(Mixer, :transition)

    state = :sys.get_state(Mixer)
    assert state.rendered_app == new_app
    assert match?({:in, _}, state.transition)
  end
end
