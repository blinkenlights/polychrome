import Config

# =============================================================================
# RADAR RUNTIME CONFIGURATION
# =============================================================================
#
# Radar config has two layers:
#
#   * Installation (logical) — the active installation module's `:radar` block
#     defines how many sensors exist, their ids, and how they are arranged.
#     See `Octopus.Installation.Nation2026`.
#
#   * Deployment (physical) — the map below binds those logical sensor ids to
#     the serial ports of a specific machine. The active entry is selected
#     automatically by the machine's short hostname, so no environment variable
#     is needed. Hosts without a matching entry (e.g. dev laptops) get no
#     physical bindings: Live mode is unavailable and Mock mode uses synthetic
#     ports.
#
# Boot source mode (`:off`|`:live`|`:exact`|`:fuzzy`) defaults to `:off` in dev
# and `:live` in prod; override with RADAR_SOURCE_MODE when a host needs a
# different mode at boot.

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

{:ok, hostname_charlist} = :inet.gethostname()

# Normalise to the short hostname so an FQDN still matches (e.g. under
# network_mode: host the container inherits the host's name, "redlady").
hostname =
  hostname_charlist
  |> List.to_string()
  |> String.split(".")
  |> hd()

config :octopus, :radar_deployment, Map.get(deployments, hostname)

default_boot_source_mode =
  case config_env() do
    :dev -> :off
    :test -> :off
    _ -> :live
  end

boot_source_mode =
  case System.get_env("RADAR_SOURCE_MODE") do
    "off" -> :off
    "live" -> :live
    "exact" -> :exact
    "fuzzy" -> :fuzzy
    _ -> default_boot_source_mode
  end

config :octopus, Octopus.Radar, boot_source_mode: boot_source_mode
