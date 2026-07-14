defmodule Octopus.Radar.DeploymentTest do
  use ExUnit.Case, async: true

  alias Octopus.Radar.{Deployment, SensorPlan}

  @installation_radar [
    defaults: [sensitivity: :normal, height_cm: 500],
    layout: [
      type: :radial,
      sensors: [:a, :b, :c, :d, :e, :f],
      start_angle_deg: 0,
      distance_cm: 300,
      rotation_deg: 0
    ]
  ]

  @linux_deployment [
    target: :linux,
    defaults: [type: :ld6001a, baud: 115_200],
    adapters: [
      [
        name: "65",
        usb_path: "1-1.4",
        ports: [
          if00: "/dev/ttyUSB0",
          if02: "/dev/ttyUSB1",
          if04: "/dev/ttyUSB2"
        ]
      ],
      [
        name: "FF",
        usb_path: "1-1.3",
        ports: [
          if00: "/dev/ttyUSB3",
          if02: "/dev/ttyUSB4",
          if04: "/dev/ttyUSB5"
        ]
      ]
    ],
    sensors: [
      [id: :a, adapter: "65", port: :if00],
      [id: :b, adapter: "65", port: :if02],
      [id: :c, adapter: "65", port: :if04],
      [id: :d, adapter: "FF", port: :if00],
      [id: :e, adapter: "FF", port: :if02],
      [id: :f, adapter: "FF", port: :if04]
    ]
  ]

  describe "resolve_port/2" do
    test "resolves adapter port references" do
      registry = Deployment.port_registry(@linux_deployment)

      assert {:ok, "/dev/ttyUSB0"} =
               Deployment.resolve_port([id: :a, adapter: "65", port: :if00], registry)

      assert {:ok, "/dev/ttyUSB5"} =
               Deployment.resolve_port([id: :f, adapter: "FF", port: :if04], registry)
    end

    test "still supports direct port paths" do
      assert {:ok, "/dev/ttyUSB9"} =
               Deployment.resolve_port([id: :a, port: "/dev/ttyUSB9"], %{})
    end

    test "returns error for unknown adapter port" do
      registry = Deployment.port_registry(@linux_deployment)

      assert {:error, {:unknown_port, "65", :missing}} =
               Deployment.resolve_port([id: :a, adapter: "65", port: :missing], registry)
    end
  end

  describe "host_target/0" do
    test "returns :linux or :macos on Unix" do
      assert Deployment.host_target() in [:linux, :macos, nil]
    end
  end

  describe "discover_ports_for_serial/2" do
    test "returns empty list when no adapter is present" do
      assert Deployment.discover_ports_for_serial("NONEXISTENT999", @linux_deployment) == []
    end

    test "skips by-id discovery when deployment target is macos" do
      macos = [target: :macos]

      assert Deployment.discover_ports_for_serial("BD6545ABCD", macos) == []

      assert {:error, :unsupported_target} =
               Deployment.usb_path_for_port(
                 "/dev/serial/by-id/usb-WCH.CN_USB_Quad_Serial_BD6545ABCD-if00",
                 macos
               )
    end
  end

  describe "enrich/1" do
    test "keeps explicit ports when serial discovery finds nothing" do
      deployment = [
        target: :linux,
        adapters: [[name: "65", serial: "NONEXISTENT999", ports: [if00: "/dev/ttyUSB0"]]],
        sensors: [[id: :a, adapter: "65", port: :if00]]
      ]

      assert [adapter | _] = Keyword.fetch!(Deployment.enrich(deployment), :adapters)
      assert adapter[:ports] == [if00: "/dev/ttyUSB0"]
    end
  end

  describe "adapters/2" do
    test "groups device ids by adapter from sensor bindings" do
      adapters = Deployment.adapters(@linux_deployment, @installation_radar)

      assert [%{name: "65", usb_path: "1-1.4", device_ids: [1, 2, 3]},
              %{name: "FF", usb_path: "1-1.3", device_ids: [4, 5, 6]}] = adapters
    end

    test "returns empty list when adapters are not configured" do
      deployment = Keyword.delete(@linux_deployment, :adapters)
      assert Deployment.adapters(deployment, @installation_radar) == []
    end
  end

  describe "integration with SensorPlan" do
    test "live mode resolves adapter references into serial ports" do
      configs = SensorPlan.build(@installation_radar, @linux_deployment, :live)

      assert {1, cfg_a} = Enum.at(configs, 0)
      assert cfg_a[:sensor_id] == :a
      assert cfg_a[:port] == "/dev/ttyUSB0"

      assert {6, cfg_f} = Enum.at(configs, 5)
      assert cfg_f[:sensor_id] == :f
      assert cfg_f[:port] == "/dev/ttyUSB5"
    end

    test "deployment_bound?/2 accepts adapter-based bindings" do
      assert SensorPlan.deployment_bound?(@installation_radar, @linux_deployment)
    end
  end
end
