import Config

# Redlady radar configuration — deployed to /data/radar.local.exs on the Pi.
# See config/radar.local.exs.example for full documentation.

# Disable radar entirely on this host:
# config :octopus, Octopus.Radar, enabled: false

# 6 sensors on two USB quad-serial adapters (WCH CH348), mounted on beams
# extending from a central mast at 60° intervals. All sensors share the same
# height and mount distance from center.
#
# Sensor-to-angle assignment (1-based device_id matches port order):
#   #1  0°   usb-WCH.CN_USB_Quad_Serial_BDFFDFABCD-if00
#   #2  60°  usb-WCH.CN_USB_Quad_Serial_BDFFDFABCD-if02
#   #3  120° usb-WCH.CN_USB_Quad_Serial_BDFFDFABCD-if04
#   #4  180° usb-WCH.CN_USB_Quad_Serial_BD6545ABCD-if00
#   #5  240° usb-WCH.CN_USB_Quad_Serial_BD6545ABCD-if02
#   #6  300° usb-WCH.CN_USB_Quad_Serial_BD6545ABCD-if04
#
# rotation_deg is relative to the outward beam direction:
#   0   = sensor local frame aligned with beam pointing away from center
#   180 = sensor facing inward toward center
# Adjust rotation_deg once here to match the physical mounting direction.
# Add a per-port keyword override for individual misalignment corrections.

config :octopus, Octopus.Radar,
  layout: [
    type: :radial,
    count: 6,
    start_angle_deg: 0,
    distance_cm: 150,
    # TODO: set to 180 if sensors face inward toward center
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
  ports: [
    "/dev/serial/by-id/usb-WCH.CN_USB_Quad_Serial_BDFFDFABCD-if00",
    "/dev/serial/by-id/usb-WCH.CN_USB_Quad_Serial_BDFFDFABCD-if02",
    "/dev/serial/by-id/usb-WCH.CN_USB_Quad_Serial_BDFFDFABCD-if04",
    "/dev/serial/by-id/usb-WCH.CN_USB_Quad_Serial_BD6545ABCD-if00",
    "/dev/serial/by-id/usb-WCH.CN_USB_Quad_Serial_BD6545ABCD-if02",
    "/dev/serial/by-id/usb-WCH.CN_USB_Quad_Serial_BD6545ABCD-if04"
  ]
