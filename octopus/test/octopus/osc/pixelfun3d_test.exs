defmodule Octopus.Osc.Pixelfun3DTest do
  use ExUnit.Case, async: false

  alias Octopus.{AppSupervisor, InstallationTransport}
  alias Octopus.Apps.{PixelFun, PixelFun3D}
  alias Octopus.Osc.Pixelfun3D, as: OscPixelfun3D
  alias Octopus.Osc.{SoftTakeover, UiSync}

  @classic_3d "pixelfun3d:classic_ripple"
  @client :local

  setup do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Octopus.Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)

    if transport_pid = Process.whereis(Octopus.InstallationTransport) do
      Ecto.Adapters.SQL.Sandbox.allow(Octopus.Repo, self(), transport_pid)
    end

    ensure_soft_takeover!()
    SoftTakeover.reset!()

    for {_, app_id} <- AppSupervisor.running_apps(), do: AppSupervisor.stop_app(app_id)

    InstallationTransport.reset!()
    InstallationTransport.set_interval(300)
    InstallationTransport.set_transition_duration(0)

    on_exit(fn ->
      for {_, app_id} <- AppSupervisor.running_apps(), do: AppSupervisor.stop_app(app_id)
      InstallationTransport.reset!()
      SoftTakeover.reset!()
    end)

    :ok
  end

  defp ensure_soft_takeover! do
    case Process.whereis(SoftTakeover) do
      nil -> start_supervised!(SoftTakeover)
      _pid -> :ok
    end
  end

  defp sync_client! do
    SoftTakeover.mark_matched_many(@client, UiSync.takeover_keys())
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

  describe "handle/3" do
    test "marks legacy params for Params fallthrough" do
      assert OscPixelfun3D.handle(["time_scale"], [1.5], @client) == :legacy
      assert OscPixelfun3D.handle(["value_percent"], [80.0], @client) == :legacy
      assert OscPixelfun3D.handle(["easing_interval"], [200.0], @client) == :legacy
    end

    test "rejects unknown paths" do
      assert OscPixelfun3D.handle(["nope"], [1.0], @client) == :unknown
      assert OscPixelfun3D.handle(["scenes", "classic_ripple"], [1.0], @client) == :unknown
    end

    test "ignores tweakables when PixelFun3D is not live" do
      assert OscPixelfun3D.handle(["zoom_base"], [2.0], @client) == :ignored
    end

    test "applies continuous tweakables when matched (UI-synced)" do
      assert :ok = InstallationTransport.play_now(PixelFun3D, @classic_3d)
      sync_client!()

      assert OscPixelfun3D.handle(["zoom_base"], [2.5], @client) == :handled
      assert OscPixelfun3D.handle(["brightness_percent"], [70.0], @client) == :handled
      assert OscPixelfun3D.handle(["roll_rate"], [-15.0], @client) == :handled

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

    test "holds continuous values until soft takeover pickup" do
      assert :ok = InstallationTransport.play_now(PixelFun3D, @classic_3d)
      SoftTakeover.reset!()

      actual = InstallationTransport.get_state().now_playing.effective[:zoom_base]
      refute actual == 2.5

      assert OscPixelfun3D.handle(["zoom_base"], [2.5], @client) == :held
      assert InstallationTransport.get_state().now_playing.effective[:zoom_base] == actual

      assert OscPixelfun3D.handle(["zoom_base"], [actual], @client) == :handled
      assert SoftTakeover.matched?(@client, :zoom_base)

      assert OscPixelfun3D.handle(["zoom_base"], [2.5], @client) == :handled
      assert InstallationTransport.get_state().now_playing.effective[:zoom_base] == 2.5
    end

    test "applies toggles and time_direction including TouchOSC floats" do
      assert :ok = InstallationTransport.play_now(PixelFun3D, @classic_3d)

      assert OscPixelfun3D.handle(["time_frozen"], [1.0], @client) == :handled
      assert OscPixelfun3D.handle(["time_direction"], ["backward"], @client) == :handled

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

      assert OscPixelfun3D.handle(["zoom_base"], [3.0], @client) == :ignored

      np = InstallationTransport.get_state().now_playing
      refute Map.get(np.effective, :zoom_base) == 3.0
    end

    test "config trigger requests sync" do
      assert OscPixelfun3D.handle(["config"], [1.0], @client) == :sync
      assert OscPixelfun3D.handle(["config"], [0.0], @client) == :ignored
    end
  end

  describe "scene fire" do
    test "fires known slug, hard-cuts, and forces motion autos off" do
      assert :ok = InstallationTransport.play_now(PixelFun3D, @classic_3d)

      # classic_ripple builtin has trans_auto true in preset JSON
      assert OscPixelfun3D.handle(["scenes", "classic_ripple", "fire"], [1.0], @client) ==
               :handled

      np = InstallationTransport.get_state().now_playing
      assert np.mode_id == @classic_3d
      assert np.effective[:trans_auto] == false
      assert np.effective[:rot_auto] == false
      assert np.effective[:zoom_auto] == false
      assert np.effective[:sway_auto] == false
      assert np.effective[:sat_auto] == false
      # palette_auto stays as in preset (classic_ripple: true)
      assert np.effective[:palette_auto] == true
    end

    test "switches to another curated scene" do
      assert :ok = InstallationTransport.play_now(PixelFun3D, @classic_3d)
      assert OscPixelfun3D.handle(["scenes", "marmor", "fire"], [1.0], @client) == :handled

      np = InstallationTransport.get_state().now_playing
      assert np.mode_id == "pixelfun3d:marmor"
      assert np.app == PixelFun3D
    end

    test "can start PixelFun3D from another live app" do
      assert :ok = InstallationTransport.play_now(PixelFun, "pixelfun:classic_ripple")
      assert OscPixelfun3D.handle(["scenes", "nordlicht", "fire"], [1.0], @client) == :handled

      np = InstallationTransport.get_state().now_playing
      assert np.app == PixelFun3D
      assert np.mode_id == "pixelfun3d:nordlicht"
    end

    test "ignores button release and unknown slugs" do
      assert :ok = InstallationTransport.play_now(PixelFun3D, @classic_3d)
      assert OscPixelfun3D.handle(["scenes", "classic_ripple", "fire"], [0.0], @client) == :ignored
      assert OscPixelfun3D.handle(["scenes", "does_not_exist", "fire"], [1.0], @client) == :ignored
    end
  end

  describe "panic" do
    test "freezes time and zeros motion without touching brightness" do
      assert :ok = InstallationTransport.play_now(PixelFun3D, @classic_3d)
      InstallationTransport.set_tweakable(:brightness_percent, 77)
      InstallationTransport.set_tweakable(:roll_rate, 40.0)
      InstallationTransport.set_tweakable(:orbit_rate, 12.0)

      assert OscPixelfun3D.handle(["panic"], [1.0], @client) == :handled

      np = InstallationTransport.get_state().now_playing
      assert np.effective[:time_frozen] == true
      assert np.effective[:roll_rate] == 0.0
      assert np.effective[:orbit_rate] == 0.0
      assert np.effective[:elev_base] == 0.0
      assert np.effective[:tilt_scale] == 0.0
      assert np.effective[:brightness_percent] == 77
      assert np.effective[:trans_auto] == false
    end

    test "ignores panic when PixelFun3D is not live" do
      assert OscPixelfun3D.handle(["panic"], [1.0], @client) == :ignored
    end

    test "ignores panic button release" do
      assert :ok = InstallationTransport.play_now(PixelFun3D, @classic_3d)
      assert OscPixelfun3D.handle(["panic"], [0.0], @client) == :ignored
    end
  end
end
