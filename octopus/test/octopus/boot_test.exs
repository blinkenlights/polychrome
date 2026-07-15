defmodule Octopus.BootTest do
  use ExUnit.Case, async: false

  alias Octopus.{AppSupervisor, Boot, InstallationTransport}
  alias Octopus.Apps.PixelFun

  @classic "pixelfun:classic_ripple"

  setup do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Octopus.Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)

    if transport_pid = Process.whereis(InstallationTransport) do
      Ecto.Adapters.SQL.Sandbox.allow(Octopus.Repo, self(), transport_pid)
    end

    for {_, app_id} <- AppSupervisor.running_apps(), do: AppSupervisor.stop_app(app_id)

    InstallationTransport.reset!()
    InstallationTransport.set_transition_duration(1.0)

    on_exit(fn ->
      for {_, app_id} <- AppSupervisor.running_apps(), do: AppSupervisor.stop_app(app_id)
      InstallationTransport.reset!()
    end)

    :ok
  end

  test "resolve_module accepts short Apps name" do
    assert {:ok, Octopus.Apps.SampleApp} = Boot.resolve_module("SampleApp")
  end

  test "resolve_module accepts full module name" do
    assert {:ok, Octopus.Apps.SampleApp} = Boot.resolve_module("Octopus.Apps.SampleApp")
  end

  test "resolve_module returns not_found for unknown apps" do
    assert {:error, :not_found} = Boot.resolve_module("DefinitelyNotAnApp")
  end

  test "start_configured_app is a no-op without boot_app config" do
    prev = Application.get_env(:octopus, :boot_app)
    Application.delete_env(:octopus, :boot_app)

    on_exit(fn ->
      if prev,
        do: Application.put_env(:octopus, :boot_app, prev),
        else: Application.delete_env(:octopus, :boot_app)
    end)

    assert :ok = Boot.start_configured_app()
  end

  test "start_app populates InstallationTransport now_playing with tweakables" do
    assert {:ok, app_id} = Boot.start_app("PixelFun", @classic)
    assert is_binary(app_id)

    np = InstallationTransport.get_state().now_playing
    assert np.app == PixelFun
    assert np.mode_id == @classic
    assert np.app_id == app_id
    assert np.tweakables != []
  end

  test "start_app restores transition duration after immediate play" do
    InstallationTransport.set_transition_duration(1.5)

    assert {:ok, _} = Boot.start_app("PixelFun", @classic)
    assert InstallationTransport.get_state().transition_duration_seconds == 1.5
  end
end
