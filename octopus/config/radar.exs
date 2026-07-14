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
#     serial ports. The active entry is selected by host OS (`:linux` or
#     `:macos`), not hostname. Hosts with no matching entry (e.g. Windows) get
#     no physical bindings: Live mode is unavailable and Mock mode uses
#     synthetic ports.
#
# Deployment format:
#
#   * `:target` — `:linux` or `:macos`; drives USB discovery behaviour for
#     this entry. Must match the runtime OS for the entry to be selected.
#
#   * `:adapters` — USB quad-serial adapters. Each adapter has a display
#     `:name` and a stable `:serial` (the id embedded in
#     `/dev/serial/by-id/usb-WCH.CN_USB_Quad_Serial_<serial>-if*`).
#     On `:target :linux`, Octopus discovers by-id port paths and sysfs
#     `usb_path` at runtime. On `:target :macos`, supply explicit `:ports`
#     (and optional `:usb_path`) instead.
#
#   * `:sensors` — maps each installation sensor id to an adapter port:
#     `[id: :a, adapter: "65", port: :if00]`. Direct `[id: :a, port: "..."]`
#     paths are still supported for simple setups without adapters.
#
# Boot source mode (`:off`|`:live`|`:exact`|`:fuzzy`) defaults to `:off` in dev
# and `:live` in prod; override with RADAR_SOURCE_MODE when a host needs a
# different mode at boot.

deployments = %{
  linux: [
    target: :linux,
    # Nation 2026 sensor rig — production Linux hosts (e.g. redlady).
    defaults: [type: :ld6001a, baud: 115_200],
    adapters: [
      [name: "65", serial: "BD6545ABCD"],
      [name: "FF", serial: "BDFFDFABCD"]
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
}

config :octopus, :radar_deployment,
       Map.get(deployments, Octopus.Radar.Deployment.host_target())

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
