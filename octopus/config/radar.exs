import Config

# =============================================================================
# RADAR SENSOR CONFIGURATION — central registry of named setups
# =============================================================================
#
# HLK-LD6001A-60G human-tracking radar modules connected over a USB-to-UART
# adapter. Loaded at runtime via config/runtime.exs (not compile time).
#
# All radar setups live here, keyed by name. Each deployment selects one via
# the RADAR_SETUP env var (set in deploy/<host>/.env); local development
# defaults to "dev" when RADAR_SETUP is unset. This is the single place to
# find or add a radar setup — there are no per-machine radar.local.exs files.
#
# :enabled is the master switch for the whole radar layer. A setup may set it
# (e.g. metaebene has no hardware), and RADAR_ENABLED (true/1/yes vs anything
# else) overrides it at runtime when present.
#
# Within a setup, each entry in :sensors is one physical device. The list
# position determines the integer device_id (1, 2, ...) used in PubSub
# messages and in Octopus.Radar.subscribe/1 / topic/1. Only :port is required
# per sensor; any omitted key falls back to :defaults.
#
# Two configuration styles are supported (see Octopus.Radar moduledoc):
#   * manual — an explicit :sensors list (+ optional :defaults)
#   * layout — a uniform :layout block + :ports/:adapters
#
# All available per-sensor keys (only :port is required):
#   port:            serial device path (required)
#   type:            :ld6001a — only supported driver today
#   enabled:         skip this sensor at boot when false
#   baud:            serial speed; our units use 115_200 (manual default is 921_600)
#   angle_deg:       bearing of sensor mount from installation center, 0..360° (CCW)
#   distance_cm:     distance from center to sensor mount, >= 0
#   rotation_deg:    sensor yaw RELATIVE TO THE OUTWARD BEAM DIRECTION (angle_deg):
#                      0   = sensor local frame aligned with beam pointing away from center
#                      180 = sensor facing inward toward center
#                    Effective global rotation = angle_deg + rotation_deg.
#   sensitivity:     AT+DPKTH, 1..9 — higher number = lower sensitivity (fewer phantoms)
#   height_cm:       mounting height (manual §9.3)
#   range_cm:        max detection range
#   x_pos_cm:        +X extent of detection volume
#   x_neg_cm:        -X extent of detection volume
#   y_pos_cm:        +Y extent of detection volume
#   y_neg_cm:        -Y extent of detection volume
#   moving_decisecs: moving-target persistence, units of 100 ms (manual §9.4)
#   static_decisecs: static-target persistence, units of 100 ms
#   exit_decisecs:   exit-zone persistence, units of 100 ms
#
# Circuits.UART uses tty.* on Linux/Pi; on Mac use tty.* (not cu.*).

# Shared per-sensor defaults. A setup's :defaults / :layout values override
# these, and per-sensor entries override those in turn.
defaults = [
  type: :ld6001a,
  enabled: true,
  # Pose: maps sensor-local x/y into the installation global frame.
  # Origin is the installation center; 0° = +X (right), 90° = +Y (front).
  angle_deg: 0,
  distance_cm: 0,
  rotation_deg: 0,
  # 115_200 matches our hardware. Manual §22.1 lists 921_600 as a documented
  # default, but the same manual's host-tool example uses 115_200, and our
  # specific HLK-LD6001A-60G unit only responds at 115_200.
  baud: 115_200,
  # Long-distance detection sensitivity (AT+DPKTH, range 1..9, default 4).
  # Counter-intuitively, a HIGHER number means LOWER sensitivity.
  sensitivity: 4,
  # Device geometry in centimeters (manual §9.3)
  height_cm: 500,
  range_cm: 500,
  x_pos_cm: 500,
  x_neg_cm: -500,
  y_pos_cm: 500,
  y_neg_cm: -500,
  # Disappearance timing in 100 ms units (manual §9.4).
  moving_decisecs: 110,
  static_decisecs: 100,
  exit_decisecs: 5
]

# All known radar setups, keyed by name. Select one per deployment with
# RADAR_SETUP=<name>.
setups = %{
  # Local Mac development. Six mock sensors arranged in a radial circle.
  # Runs mock-backed (boot_mock_mode :exact), so the placeholder ports below
  # are never opened for real hardware. Tune the sensor-circle radius via
  # :distance_cm, the mounting height via :height_cm, and the simulated
  # world-disk radius (where mock people roam) via mock: [radius_m: ...].
  "dev" => [
    defaults: defaults,
    layout: [
      type: :radial,
      count: 6,
      start_angle_deg: 0,
      distance_cm: 300,
      rotation_deg: 90,
      height_cm: 250
    ],
    # Mock mode never opens these ports for real, so placeholder paths are fine.
    ports: [
      "/dev/tty.mock-radar-1",
      "/dev/tty.mock-radar-2",
      "/dev/tty.mock-radar-3",
      "/dev/tty.mock-radar-4",
      "/dev/tty.mock-radar-5",
      "/dev/tty.mock-radar-6"
    ],
    mock: [radius_m: 9.0]
  ],

  # metaebene.org production server — no radar hardware.
  "metaebene" => [
    enabled: false,
    sensors: []
  ],

  # Redlady (Raspberry Pi). 6 sensors on two USB quad-serial adapters
  # (WCH CH348), mounted on beams extending from a central mast at 60°
  # intervals. All sensors share the same height and mount distance.
  #
  # Adapter "FF" (sysfs 1-1.3, USB serial BDFFDFABCD) — sensors A,B,C (#1–#3)
  # Adapter "65" (sysfs 1-1.4, USB serial BD6545ABCD) — sensors D,E,F (#4–#6)
  #
  # rotation_deg is relative to the outward beam direction; 90 matches the
  # physical mounting direction.
  "redlady" => [
    defaults: defaults,
    layout: [
      type: :radial,
      count: 6,
      start_angle_deg: 0,
      distance_cm: 300,
      rotation_deg: 90,
      sensitivity: 4,
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
  ]
}

setup_name = System.get_env("RADAR_SETUP", "dev")

setup =
  Map.get(setups, setup_name) ||
    raise "Unknown RADAR_SETUP #{inspect(setup_name)}; known: #{inspect(Map.keys(setups))}"

# RADAR_ENABLED overrides the setup's :enabled when present.
enabled? =
  case System.get_env("RADAR_ENABLED") do
    nil -> Keyword.get(setup, :enabled, true)
    val -> val in ~w(true 1 yes)
  end

# Boot-time mock mode (see Octopus.Radar.boot_mock_mode/0). The "dev" setup has
# no real hardware, so it defaults to :exact (mock-backed sensors stream a
# simulated crowd from boot); all other setups default to :off (real serial).
# Override anywhere with RADAR_MOCK_MODE=off|exact|fuzzy.
boot_mock_mode =
  System.get_env("RADAR_MOCK_MODE", if(setup_name == "dev", do: "exact", else: "off"))
  |> String.to_existing_atom()

config :octopus,
       Octopus.Radar,
       Keyword.merge(setup, enabled: enabled?, boot_mock_mode: boot_mock_mode)
