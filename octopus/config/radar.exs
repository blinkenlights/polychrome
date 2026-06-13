import Config

# =============================================================================
# RADAR SENSOR CONFIGURATION
# =============================================================================
#
# HLK-LD6001A-60G human-tracking radar modules connected over a USB-to-UART
# adapter. Loaded at runtime via config/runtime.exs (not compile time).
#
# Each entry in :sensors is one physical device. The list position determines
# the integer device_id (1, 2, ...) used in PubSub messages and in
# Octopus.Radar.subscribe/1 / topic/1.
#
# :enabled — master switch for the whole radar layer (also overridable via
# RADAR_ENABLED env: true/1/yes vs anything else).
#
# Only :port is required per sensor. Any omitted key falls back to :defaults.
# Per-machine overrides: copy radar.local.exs.example to radar.local.exs
# (gitignored).
#
# Circuits.UART uses tty.* on Linux/Pi; on Mac use tty.* (not cu.*).

config :octopus, Octopus.Radar,
  enabled: System.get_env("RADAR_ENABLED", "true") in ~w(true 1 yes),
  sensors: [
    [port: "/dev/tty.usbmodemBD6545ABCD1"],
    [port: "/dev/tty.usbmodemBD6545ABCD3"],
    [port: "/dev/tty.usbmodemBD6545ABCD5"]
  ],
  defaults: [
    type: :ld6001a,
    enabled: true,
    # Pose: maps sensor-local x/y into the installation global frame.
    # Origin is the installation center; 0° = +X (right), 90° = +Y (front).
    # rotation_deg is relative to the outward beam direction (angle_deg):
    #   0   = sensor local frame aligned with beam pointing away from center
    #   180 = sensor facing inward toward center
    # Effective global rotation applied = angle_deg + rotation_deg.
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
    height_cm: 320,
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
  ]
