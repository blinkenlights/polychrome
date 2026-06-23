import Config

# Redlady radar configuration — deployed to /data/radar.local.exs on the Pi.
# See config/radar.local.exs.example for full documentation.

# 6 sensors on two USB quad-serial adapters (WCH CH348), mounted on beams
# extending from a central mast at 60° intervals. All sensors share the same
# height and mount distance from center.
#
# Adapter "FF" (sysfs 1-1.3, USB serial BDFFDFABCD) — sensors A,B,C (#1–#3)
# Adapter "65" (sysfs 1-1.4, USB serial BD6545ABCD) — sensors D,E,F (#4–#6)
#
# rotation_deg is relative to the outward beam direction:
#   0   = sensor local frame aligned with beam pointing away from center
#   90  = sensor rotated 90° (as physically mounted)
# Adjust rotation_deg once here to match the physical mounting direction.

config :octopus, Octopus.Radar,
  layout: [
    type: :radial,
    count: 6,
    start_angle_deg: 0,
    distance_cm: 150,
    rotation_deg: 90,
    baud: 115_200,
    sensitivity: 4,
    height_cm: 450,
    range_cm: 450,
    x_pos_cm: 450,
    x_neg_cm: -450,
    y_pos_cm: 450,
    y_neg_cm: -450,
    moving_decisecs: 110,
    static_decisecs: 100,
    exit_decisecs: 5
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
