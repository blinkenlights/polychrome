defmodule Octopus.AppBleedingTest do
  use ExUnit.Case, async: false

  alias Octopus.{App, AppSupervisor}
  alias Octopus.Apps.CanvasTest

  setup do
    on_exit(fn ->
      AppSupervisor.running_apps()
      |> Enum.each(fn {_, app_id} -> AppSupervisor.stop_app(app_id) end)
    end)

    :ok
  end

  test "config_schema/1 includes bleeding with default 0.0" do
    assert {:bleeding, {"Bleeding", :float, opts}} =
             App.config_schema(CanvasTest) |> Enum.find(fn {key, _} -> key == :bleeding end)

    assert opts[:default] == 0.0
  end

  test "start_app defaults bleeding to 0.0 when not specified" do
    assert {:ok, app_id} = AppSupervisor.start_app(CanvasTest)
    assert AppSupervisor.config(app_id).bleeding == 0.0
  end

  test "start_app accepts bleeding directly in config" do
    assert {:ok, app_id} = AppSupervisor.start_app(CanvasTest, config: %{bleeding: 42.0})
    assert AppSupervisor.config(app_id).bleeding == 42.0
  end

  test "update_config clamps bleeding to 0..100" do
    assert {:ok, app_id} = AppSupervisor.start_app(CanvasTest)

    :ok = AppSupervisor.update_config(app_id, %{bleeding: 150.0})
    assert AppSupervisor.config(app_id).bleeding == 100.0

    :ok = AppSupervisor.update_config(app_id, %{bleeding: -5.0})
    assert AppSupervisor.config(app_id).bleeding == 0.0
  end

  test "clamp_bleeding/1 clamps values" do
    assert App.clamp_bleeding(50.0) == 50.0
    assert App.clamp_bleeding(150.0) == 100.0
    assert App.clamp_bleeding(-1.0) == 0.0
  end
end
