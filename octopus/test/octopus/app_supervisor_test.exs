defmodule Octopus.AppSupervisorTest do
  use ExUnit.Case, async: false
  alias Octopus.{AppSupervisor, App}

  test "get_installation_info returns expected data" do
    info = App.get_installation_info()

    assert is_integer(info.panel_count)
    assert is_integer(info.panel_width)
    assert is_integer(info.panel_height)
    assert is_integer(info.panel_gap)
    assert is_integer(info.width)
    assert is_integer(info.height)

    # Verify calculated width matches expected value
    expected_width = info.panel_count * info.panel_width
    assert info.width >= expected_width
  end

  test "start_app works with compatible apps" do
    # Test with an app that should be compatible (Canvas Test)
    assert {:ok, app_id} = AppSupervisor.start_app(Octopus.Apps.CanvasTest)
    assert is_binary(app_id)

    # Verify it's in running apps
    running = AppSupervisor.running_apps()
    assert Enum.any?(running, fn {module, ^app_id} -> module == Octopus.Apps.CanvasTest end)

    # Clean up
    AppSupervisor.stop_app(app_id)
  end

  test "all real apps implement compatible? callback" do
    available = AppSupervisor.available_apps()

    for app_module <- available do
      # Should not raise - all apps should have compatible?/0
      result = apply(app_module, :compatible?, [])
      assert is_boolean(result)
    end
  end

  test "start_or_select_app returns existing app_id when app is already running" do
    # Start an app for the first time
    assert {:ok, app_id1} = AppSupervisor.start_or_select_app(Octopus.Apps.CanvasTest)
    assert is_binary(app_id1)

    # Verify it's in running apps
    running = AppSupervisor.running_apps()
    assert Enum.any?(running, fn {module, ^app_id1} -> module == Octopus.Apps.CanvasTest end)

    # Try to start the same app again - should return the same app_id
    assert {:ok, app_id2} = AppSupervisor.start_or_select_app(Octopus.Apps.CanvasTest)
    assert app_id1 == app_id2

    # Verify only one instance is running
    running_after = AppSupervisor.running_apps()

    canvas_test_apps =
      Enum.filter(running_after, fn {module, _} -> module == Octopus.Apps.CanvasTest end)

    assert length(canvas_test_apps) == 1

    # Clean up
    AppSupervisor.stop_app(app_id1)
  end

  test "find_running_app returns correct app_id when app is running" do
    # Start an app
    assert {:ok, app_id} = AppSupervisor.start_app(Octopus.Apps.CanvasTest)

    # find_running_app should find it
    assert {:ok, ^app_id} = AppSupervisor.find_running_app(Octopus.Apps.CanvasTest)

    # Clean up
    AppSupervisor.stop_app(app_id)
  end

  test "start_app stops other running apps" do
    assert {:ok, app_id1} = AppSupervisor.start_app(Octopus.Apps.CanvasTest)
    assert {:ok, app_id2} = AppSupervisor.start_app(Octopus.Apps.CanvasTest)

    assert app_id1 != app_id2

    running = AppSupervisor.running_apps()
    assert Enum.any?(running, fn {module, id} -> module == Octopus.Apps.CanvasTest and id == app_id2 end)
    refute Enum.any?(running, fn {_, id} -> id == app_id1 end)

    AppSupervisor.stop_app(app_id2)
  end

  test "find_running_app returns :not_found when app is not running" do
    # Ensure no Canvas Test apps are running
    AppSupervisor.running_apps()
    |> Enum.filter(fn {module, _} -> module == Octopus.Apps.CanvasTest end)
    |> Enum.each(fn {_, app_id} -> AppSupervisor.stop_app(app_id) end)

    # find_running_app should return :not_found
    assert :not_found = AppSupervisor.find_running_app(Octopus.Apps.CanvasTest)
  end
end
