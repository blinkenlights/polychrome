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
#     `[id: :a, adapter: "65", port: :if00]`. Geographic pose keys
#     (`:rotation_deg`, `:angle_deg`, …) belong in the installation module,
#     not here. Direct `[id: :a, port: "..."]` paths are supported, and can
#     be provided via environment variables: `RADAR_PORT_<id>` (e.g.
#     `RADAR_PORT_a=/dev/ttyUSB0`).
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
    sensors:
      for id <- [:a, :b, :c, :d, :e, :f] do
        env_port = System.get_env("RADAR_PORT_#{id}")

        default_binding =
          case id do
            :a -> [adapter: "65", port: :if00]
            :b -> [adapter: "65", port: :if02]
            :c -> [adapter: "65", port: :if04]
            :d -> [adapter: "FF", port: :if00]
            :e -> [adapter: "FF", port: :if02]
            :f -> [adapter: "FF", port: :if04]
          end

        if env_port && env_port != "" do
          [id: id, port: env_port]
        else
          id_opt = [id: id]
          id_opt ++ default_binding
        end
      end
  ],
  macos: [
    target: :macos,
    sensors:
      for(id <- [:a, :b, :c, :d, :e, :f], do: [id: id, port: System.get_env("RADAR_PORT_#{id}")])
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
