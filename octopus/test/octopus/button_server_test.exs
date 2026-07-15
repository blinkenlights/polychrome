defmodule Octopus.ButtonServerTest do
  use ExUnit.Case, async: false

  alias Octopus.ButtonServer

  setup do
    original_installation = Application.get_env(:octopus, :installation)

    on_exit(fn ->
      Application.put_env(:octopus, :installation, original_installation)
    end)

    %{original_installation: original_installation}
  end

  test "selected_app change with zero buttons does not crash ButtonServer" do
    Application.put_env(:octopus, :installation, Octopus.Installation.Woodstock1)

    send(ButtonServer, {:app_manager, {:selected_app, "test-app"}})
    _ = :sys.get_state(ButtonServer)

    assert Process.alive?(Process.whereis(ButtonServer))
  end

  test "ignores other app_manager and apps PubSub events" do
    send(ButtonServer, {:app_manager, {:mask_app, nil}})
    send(ButtonServer, {:app_manager, {:app_lifecycle, "app-1", :selected}})
    send(ButtonServer, {:apps, {:started, "app-1", Octopus.Apps.GravityMask}})
    send(ButtonServer, {:apps, {:config_updated, "app-1", %{}}})
    _ = :sys.get_state(ButtonServer)

    assert Process.alive?(Process.whereis(ButtonServer))
  end
end
