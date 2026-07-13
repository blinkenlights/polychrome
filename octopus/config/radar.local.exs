import Config

# Copy to radar.local.exs (gitignored) for machine-specific overrides.
# Loaded after radar.exs in config/runtime.exs.

# Leave source off on this host (default in dev):
# RADAR_SOURCE_MODE=off

# Example: three sensors around an installation center (pose values are illustrative):

config :octopus, Octopus.Radar,
  sensors: [
    #    [
    #      name: "AA",
    #      port: "/dev/tty.usbmodemBD6545ABCD1",
    #      enabled: true,
    #      angle_deg: 0,
    #      distance_cm: 0,
    #      rotation_deg: 0
    #    ],
    [
      name: "AB",
      port: "/dev/tty.usbmodemBD6545ABCD3",
      enabled: true,
      angle_deg: 60,
      distance_cm: 150,
      rotation_deg: 60
    ],
    [
      name: "AC",
      port: "/dev/tty.usbmodemBD6545ABCD5",
      enabled: true,
      angle_deg: 120,
      distance_cm: 150,
      rotation_deg: 120
    ],
    [
      name: "AD",
      port: "/dev/tty.usbmodemBD6545ABCD7",
      enabled: true,
      angle_deg: 180,
      distance_cm: 150,
      rotation_deg: 180
    ],
    #    [
    #      name: "BA",
    #      port: "/dev/tty.usbmodemBDFFDFABCD1",
    #      enabled: true,
    #      angle_deg: 180,
    #      distance_cm: 150,
    #      rotation_deg: 180
    #    ],
    [
      name: "BB",
      port: "/dev/tty.usbmodemBDFFDFABCD3",
      enabled: true,
      angle_deg: 240,
      distance_cm: 150,
      rotation_deg: 240
    ],
    [
      name: "BC",
      port: "/dev/tty.usbmodemBDFFDFABCD5",
      enabled: true,
      angle_deg: 300,
      distance_cm: 150,
      rotation_deg: 300
    ],
    [
      name: "BD",
      port: "/dev/tty.usbmodemBDFFDFABCD7",
      enabled: true,
      angle_deg: 360,
      distance_cm: 150,
      rotation_deg: 360
    ]
  ],
  defaults: [
    height_cm: 300
  ]
