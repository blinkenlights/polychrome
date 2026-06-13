import Config

# Redlady radar configuration — deployed to /data/radar.local.exs on the Pi.
# See config/radar.local.exs.example for full documentation.

# Disable radar entirely on this host:
# config :octopus, Octopus.Radar, enabled: false

# Raspberry Pi — one or two sensors on USB-to-UART adapters:
#
config :octopus, Octopus.Radar,
  defaults: [
    type: :ld6001a,
    enabled: true,
    # Pose correction: map sensor-local x/y into the installation global frame.
    # Origin is the installation center; 0° = +X (right), 90° = +Y (front).
    angle_deg: 0,
    distance_cm: 0,
    rotation_deg: 0,
    # 115_200 matches our hardware. Manual §22.1 lists 921_600 as a documented
    # default, but the same manual's host-tool example uses 115_200, and our
    # specific HLK-LD6001A-60G unit only responds at 115_200. Override per
    # sensor in the :sensors list above if a unit has been reflashed.
    baud: 115_200,
    # Long-distance detection sensitivity (AT+DPKTH, range 1..9, default 4).
    # The manual is counter-intuitive: a HIGHER number means LOWER sensitivity,
    # i.e. fewer phantom targets. Raise this if the device reports too many
    # tracks for one person; lower it if it misses real targets.
    sensitivity: 4,
    # Device geometry in centimeters (manual §9.3)
    height_cm: 450,
    range_cm: 450,
    x_pos_cm: 450,
    x_neg_cm: -450,
    y_pos_cm: 450,
    y_neg_cm: -450,
    # Disappearance timing in 100 ms units (manual §9.4). The defaults are
    # quite permissive — a track stays alive for up to 11 s after the radar
    # last saw it. If you want ghost tracks dropped faster, lower these.
    moving_decisecs: 110,
    static_decisecs: 100,
    exit_decisecs: 5
  ],
  sensors: [
    [
      port: "/dev/serial/by-id/usb-WCH.CN_USB_Quad_Serial_BDFFDFABCD-if00",
      angle_deg: 0,
      distance_cm: 150,
      rotation_deg: 0
    ],
    [
      port: "/dev/serial/by-id/usb-WCH.CN_USB_Quad_Serial_BDFFDFABCD-if02",
      angle_deg: 60,
      distance_cm: 150,
      rotation_deg: 0
    ],
    [
      port: "/dev/serial/by-id/usb-WCH.CN_USB_Quad_Serial_BDFFDFABCD-if04",
      angle_deg: 120,
      distance_cm: 150,
      rotation_deg: 0
    ],
    [
      port: "/dev/serial/by-id/usb-WCH.CN_USB_Quad_Serial_BD6545ABCD-if00",
      angle_deg: 180,
      distance_cm: 0,
      rotation_deg: 0
    ],
    [
      port: "/dev/serial/by-id/usb-WCH.CN_USB_Quad_Serial_BD6545ABCD-if02",
      angle_deg: 240,
      distance_cm: 150,
      rotation_deg: 0
    ],
    [
      port: "/dev/serial/by-id/usb-WCH.CN_USB_Quad_Serial_BD6545ABCD-if04",
      angle_deg: 300,
      distance_cm: 150,
      rotation_deg: 0
    ]
  ]
