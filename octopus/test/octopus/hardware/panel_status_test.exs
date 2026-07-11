defmodule Octopus.Hardware.PanelStatusTest do
  use ExUnit.Case, async: true

  alias Octopus.Broadcaster.FirmwareInfoMeta
  alias Octopus.Hardware.PanelSlot
  alias Octopus.Hardware.PanelStatus
  alias Octopus.Protobuf.FirmwareInfo

  @now 1_700_000_000

  describe "status_for_age_seconds/1" do
    test "online at 10 seconds" do
      assert :online = PanelStatus.status_for_age_seconds(10)
    end

    test "stale between 11 and 30 seconds" do
      assert :stale = PanelStatus.status_for_age_seconds(11)
      assert :stale = PanelStatus.status_for_age_seconds(30)
    end

    test "offline after 30 seconds" do
      assert :offline = PanelStatus.status_for_age_seconds(31)
    end

    test "offline when never seen" do
      assert :offline = PanelStatus.status_for_age(nil)
    end
  end

  describe "status_for_last_seen/2" do
    test "online when last seen recently" do
      assert :online = PanelStatus.status_for_last_seen(@now - 5, @now)
    end

    test "offline when never seen" do
      assert :offline = PanelStatus.status_for_last_seen(nil, @now)
    end
  end

  describe "all/2" do
    test "maps firmware stats to logical panel numbers by MAC" do
      controller = Octopus.Hardware.fetch!(:polychrome_panel_1)

      firmware_stats = %{
        controller.mac => meta(controller, @now - 5)
      }

      panel_slots = [
        %PanelSlot{controller_id: :polychrome_panel_1, wiring_id: :serpentine_8x8_bottom_left},
        %PanelSlot{controller_id: :polychrome_panel_2, wiring_id: :serpentine_8x8_bottom_left}
      ]

      statuses =
        PanelStatus.all(@now,
          firmware_stats: firmware_stats,
          panel_slots: panel_slots
        )

      assert [%{panel: 1, status: :online, controller_id: :polychrome_panel_1, firmware_info: %{} = info},
              %{panel: 2, status: :offline, controller_id: :polychrome_panel_2, firmware_info: nil}] =
               statuses

      assert info.mac == controller.mac
    end

    test "falls back to hostname when MAC differs" do
      controller = Octopus.Hardware.fetch!(:polychrome_panel_1)

      firmware_stats = %{
        "aa:bb:cc:dd:ee:ff" =>
          meta(
            %FirmwareInfo{
              hostname: controller.hostname,
              mac: "aa:bb:cc:dd:ee:ff",
              panel_index: 1
            },
            @now - 5
          )
      }

      panel_slots = [
        %PanelSlot{controller_id: :polychrome_panel_1, wiring_id: :serpentine_8x8_bottom_left}
      ]

      assert [%{panel: 1, status: :online}] =
               PanelStatus.all(@now,
                 firmware_stats: firmware_stats,
                 panel_slots: panel_slots
               )
    end

    test "matches firmware MAC case and hostname without .local suffix" do
      firmware_stats = %{
        "CC:DB:A7:52:F7:FB" =>
          meta(
            %FirmwareInfo{
              hostname: "blinkenleds-9",
              mac: "CC:DB:A7:52:F7:FB",
              panel_index: 9
            },
            @now - 5
          )
      }

      panel_slots = [
        %PanelSlot{controller_id: :polychrome_panel_9, wiring_id: :serpentine_vertical_bottom_left}
      ]

      assert [%{panel: 1, status: :online, controller_id: :polychrome_panel_9}] =
               PanelStatus.all(@now,
                 firmware_stats: firmware_stats,
                 panel_slots: panel_slots
               )
    end
  end

  describe "enabled?/0" do
    test "delegates to Broadcaster.sending_enabled?/0" do
      assert PanelStatus.enabled?() == Octopus.Broadcaster.sending_enabled?()
    end
  end

  defp meta(controller, last_seen) when is_struct(controller, Octopus.Hardware.Controller) do
    meta(
      %FirmwareInfo{
        hostname: controller.hostname,
        mac: controller.mac,
        panel_index: controller.firmware_panel_index
      },
      last_seen
    )
  end

  defp meta(%FirmwareInfo{} = info, last_seen) do
    %FirmwareInfoMeta{
      last_seen: last_seen,
      firmware_info: info,
      from_ip: {127, 0, 0, 1}
    }
  end
end

defmodule Octopus.BroadcasterSendingEnabledTest do
  use ExUnit.Case, async: true

  alias Octopus.Broadcaster

  test "enabled in prod regardless of send_in_dev" do
    previous = Application.get_env(:octopus, :env)

    try do
      Application.put_env(:octopus, :env, :prod)
      assert Broadcaster.config_allows_sending?(send_in_dev: false)
      assert Broadcaster.config_allows_sending?(send_in_dev: true)
    after
      Application.put_env(:octopus, :env, previous)
    end
  end

  test "disabled in dev when send_in_dev is false" do
    previous = Application.get_env(:octopus, :env)

    try do
      Application.put_env(:octopus, :env, :dev)
      refute Broadcaster.config_allows_sending?(send_in_dev: false)
    after
      Application.put_env(:octopus, :env, previous)
    end
  end

  test "enabled in dev when send_in_dev is true" do
    previous = Application.get_env(:octopus, :env)

    try do
      Application.put_env(:octopus, :env, :dev)
      assert Broadcaster.config_allows_sending?(send_in_dev: true)
    after
      Application.put_env(:octopus, :env, previous)
    end
  end

  test "set_sending_enabled toggles runtime UDP sending" do
    previous = Broadcaster.sending_enabled?()
    enabled = !previous

    try do
      Broadcaster.set_sending_enabled(enabled)
      Process.sleep(50)
      assert Broadcaster.sending_enabled?() == enabled

      Broadcaster.set_sending_enabled(previous)
      Process.sleep(50)
      assert Broadcaster.sending_enabled?() == previous
    after
      Broadcaster.set_sending_enabled(previous)
    end
  end
end
