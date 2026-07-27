defmodule Octopus.Osc.Pixelfun3DTest do
  use ExUnit.Case, async: false

  alias Octopus.{AppSupervisor, InstallationTransport}
  alias Octopus.Apps.{PixelFun, PixelFun3D}
  alias Octopus.Osc.Pixelfun3D, as: OscPixelfun3D

  @classic_3d "pixelfun3d:classic_ripple"

  setup do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Octopus.Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)

    if transport_pid = Process.whereis(Octopus.InstallationTransport) do
      Ecto.Adapters.SQL.Sandbox.allow(Octopus.Repo, self(), transport_pid)
    end

    for {_, app_id} <- AppSupervisor.running_apps(), do: AppSupervisor.stop_app(app_id)

    InstallationTransport.reset!()
    InstallationTransport.set_interval(300)
    InstallationTransport.set_transition_duration(0)

    on_exit(fn ->
      for {_, app_id} <- AppSupervisor.running_apps(), do: AppSupervisor.stop_app(app_id)
      InstallationTransport.reset!()
    end)

    :ok
  end

  describe "normalize_arg/2" do
    test "coerces TouchOSC float toggles" do
      assert OscPixelfun3D.normalize_arg("time_frozen", [1.0]) == {:ok, 1}
      assert OscPixelfun3D.normalize_arg("time_frozen", [0.0]) == {:ok, 0}
    end

    test "accepts time_direction strings" do
      assert OscPixelfun3D.normalize_arg("time_direction", ["backward"]) == {:ok, "backward"}
      assert OscPixelfun3D.normalize_arg("time_direction", ["forward"]) == {:ok, "forward"}
    end

    test "truncates integer sliders" do
      assert OscPixelfun3D.normalize_arg("brightness_percent", [72.9]) == {:ok, 72}
      assert OscPixelfun3D.normalize_arg("saturation_percent", [55.0]) == {:ok, 55}
    end

    test "keeps continuous floats" do
      assert OscPixelfun3D.normalize_arg("zoom_base", [2.5]) == {:ok, 2.5}
      assert OscPixelfun3D.normalize_arg("roll_rate", [-12]) == {:ok, -12.0}
    end
  end

  describe "handle/2" do
    test "marks legacy params for Params fallthrough" do
      assert OscPixelfun3D.handle(["time_scale"], [1.5]) == :legacy
      assert OscPixelfun3D.handle(["value_percent"], [80.0]) == :legacy
      assert OscPixelfun3D.handle(["easing_interval"], [200.0]) == :legacy
    end

    test "rejects unknown paths" do
      assert OscPixelfun3D.handle(["scenes", "classic_ripple", "fire"], [1.0]) == :unknown
      assert OscPixelfun3D.handle(["panic"], [1.0]) == :unknown
      assert OscPixelfun3D.handle(["nope"], [1.0]) == :unknown
    end

    test "ignores tweakables when PixelFun3D is not live" do
      assert OscPixelfun3D.handle(["zoom_base"], [2.0]) == :ignored
    end

    test "applies continuous tweakables via InstallationTransport" do
      assert :ok = InstallationTransport.play_now(PixelFun3D, @classic_3d)
      assert InstallationTransport.get_state().live.app == PixelFun3D

      assert OscPixelfun3D.handle(["zoom_base"], [2.5]) == :handled
      assert OscPixelfun3D.handle(["brightness_percent"], [70.0]) == :handled
      assert OscPixelfun3D.handle(["roll_rate"], [-15.0]) == :handled

      np = InstallationTransport.get_state().now_playing
      assert np.effective[:zoom_base] == 2.5
      assert np.effective[:brightness_percent] == 70
      assert np.effective[:roll_rate] == -15.0
      assert np.dirty

      {:ok, app_id} = AppSupervisor.find_running_app(PixelFun3D)
      config = AppSupervisor.config(app_id)
      assert config[:zoom_base] == 2.5
      assert config[:brightness_percent] == 70
      assert config[:roll_rate] == -15.0
    end

    test "applies toggles and time_direction including TouchOSC floats" do
      assert :ok = InstallationTransport.play_now(PixelFun3D, @classic_3d)

      assert OscPixelfun3D.handle(["time_frozen"], [1.0]) == :handled
      assert OscPixelfun3D.handle(["time_direction"], ["backward"]) == :handled

      np = InstallationTransport.get_state().now_playing
      assert np.effective[:time_frozen] == true
      assert np.effective[:time_direction] == :backward

      {:ok, app_id} = AppSupervisor.find_running_app(PixelFun3D)
      config = AppSupervisor.config(app_id)
      assert config[:time_frozen] == true
      assert config[:time_direction] == :backward
    end

    test "does not apply PixelFun3D tweakables onto another live app" do
      assert :ok = InstallationTransport.play_now(PixelFun, "pixelfun:classic_ripple")
      assert InstallationTransport.get_state().live.app == PixelFun

      assert OscPixelfun3D.handle(["zoom_base"], [3.0]) == :ignored

      np = InstallationTransport.get_state().now_playing
      refute Map.get(np.effective, :zoom_base) == 3.0
    end
  end
end
