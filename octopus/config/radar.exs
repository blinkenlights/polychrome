import Config

# =============================================================================
# RADAR RUNTIME CONFIGURATION
# =============================================================================
#
# Logical sensor layout lives in the active installation module (`:radar`).
# Physical port bindings live in config/radar_deployments.exs, selected per
# host via RADAR_DEPLOYMENT (e.g. deploy/redlady/.env).
#
# RADAR_SOURCE_MODE=off|live|exact|fuzzy (default :off in dev, :live in prod).
# RADAR_MOCK_MODE=exact|fuzzy is still accepted (maps off → live for legacy).

Code.eval_file(Path.join(__DIR__, "radar_deployments.exs"))

default_boot_source_mode =
  case config_env() do
    :dev -> :off
    :test -> :off
    _ -> :live
  end

boot_source_mode =
  case System.get_env("RADAR_SOURCE_MODE") do
    nil ->
      case System.get_env("RADAR_MOCK_MODE") do
        nil ->
          default_boot_source_mode

        "exact" ->
          :exact

        "fuzzy" ->
          :fuzzy

        # Legacy: RADAR_MOCK_MODE=off meant live serial sensors.
        "off" ->
          :live

        _ ->
          default_boot_source_mode
      end

    "off" ->
      :off

    "live" ->
      :live

    "exact" ->
      :exact

    "fuzzy" ->
      :fuzzy

    _ ->
      default_boot_source_mode
  end

config :octopus, Octopus.Radar, boot_source_mode: boot_source_mode
