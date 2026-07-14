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
end
