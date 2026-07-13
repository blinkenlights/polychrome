import Config

# =============================================================================
# RADAR DEPLOYMENT BINDINGS — maps logical sensors to physical hardware
# =============================================================================
#
# Installations define logical sensors (ids + layout) in their module under
# `:radar`. Each deployment host selects one entry here via RADAR_DEPLOYMENT
# and maps those ids to serial ports on that machine.
#
# When RADAR_DEPLOYMENT is unset, no physical bindings exist: Live mode is
# unavailable and mock mode uses synthetic /dev/tty.mock-radar-N ports.

deployments = %{
  "redlady" => [
    defaults: [type: :ld6001a, baud: 115_200],
    sensors: [
      [
        id: :a,
        port: "/dev/serial/by-id/usb-WCH.CN_USB_Quad_Serial_BDFFDFABCD-if00"
      ],
      [
        id: :b,
        port: "/dev/serial/by-id/usb-WCH.CN_USB_Quad_Serial_BDFFDFABCD-if02"
      ],
      [
        id: :c,
        port: "/dev/serial/by-id/usb-WCH.CN_USB_Quad_Serial_BDFFDFABCD-if04"
      ],
      [
        id: :d,
        port: "/dev/serial/by-id/usb-WCH.CN_USB_Quad_Serial_BD6545ABCD-if00"
      ],
      [
        id: :e,
        port: "/dev/serial/by-id/usb-WCH.CN_USB_Quad_Serial_BD6545ABCD-if02"
      ],
      [
        id: :f,
        port: "/dev/serial/by-id/usb-WCH.CN_USB_Quad_Serial_BD6545ABCD-if04"
      ]
    ],
    adapters: [
      [
        name: "FF",
        usb_path: "1-1.3",
        ports: [
          "/dev/serial/by-id/usb-WCH.CN_USB_Quad_Serial_BDFFDFABCD-if00",
          "/dev/serial/by-id/usb-WCH.CN_USB_Quad_Serial_BDFFDFABCD-if02",
          "/dev/serial/by-id/usb-WCH.CN_USB_Quad_Serial_BDFFDFABCD-if04"
        ]
      ],
      [
        name: "65",
        usb_path: "1-1.4",
        ports: [
          "/dev/serial/by-id/usb-WCH.CN_USB_Quad_Serial_BD6545ABCD-if00",
          "/dev/serial/by-id/usb-WCH.CN_USB_Quad_Serial_BD6545ABCD-if02",
          "/dev/serial/by-id/usb-WCH.CN_USB_Quad_Serial_BD6545ABCD-if04"
        ]
      ]
    ]
  ]
}

deployment_name = System.get_env("RADAR_DEPLOYMENT")

deployment =
  case deployment_name do
    nil ->
      nil

    name ->
      Map.get(deployments, name) ||
        raise "Unknown RADAR_DEPLOYMENT #{inspect(name)}; known: #{inspect(Map.keys(deployments))}"
  end

config :octopus, :radar_deployment, deployment
