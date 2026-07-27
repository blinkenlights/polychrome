defmodule Octopus.Osc.UiSyncTest do
  use ExUnit.Case, async: false

  alias Octopus.{AppSupervisor, InstallationTransport}
  alias Octopus.Apps.PixelFun3D
  alias Octopus.Osc.UiSync

  @classic_3d "pixelfun3d:classic_ripple"

  setup do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Octopus.Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)

    if transport_pid = Process.whereis(Octopus.InstallationTransport) do
      Ecto.Adapters.SQL.Sandbox.allow(Octopus.Repo, self(), transport_pid)
    end

    for {_, app_id} <- AppSupervisor.running_apps(), do: AppSupervisor.stop_app(app_id)
    InstallationTransport.reset!()
    InstallationTransport.set_transition_duration(0)

    on_exit(fn ->
      for {_, app_id} <- AppSupervisor.running_apps(), do: AppSupervisor.stop_app(app_id)
      InstallationTransport.reset!()
    end)

    :ok
  end

  test "snapshot includes tweaks when PixelFun3D is live" do
    assert :ok = InstallationTransport.play_now(PixelFun3D, @classic_3d)
    snap = UiSync.snapshot()

    assert is_number(snap.global_speed)
    assert is_map(snap.tweaks)
    assert Map.has_key?(snap.tweaks, :zoom_base)
    assert Map.has_key?(snap.tweaks, :time_frozen)
  end

  test "messages encode app-unit OSC addresses" do
    assert :ok = InstallationTransport.play_now(PixelFun3D, @classic_3d)
    msgs = UiSync.messages(UiSync.snapshot())

    addresses = Enum.map(msgs, & &1.address)
    assert "/global/speed" in addresses
    assert "/pixelfun3d/zoom_base" in addresses
    assert "/pixelfun3d/time_direction" in addresses
  end
end
