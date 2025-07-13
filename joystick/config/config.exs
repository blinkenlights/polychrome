# This file is responsible for configuring your application and its
# dependencies.
#
# This configuration file is loaded before any dependency and is restricted to
# this project.
import Config

# Enable the Nerves integration with Mix
Application.start(:nerves_bootstrap)

config :joystick, target: Mix.target()

# =============================================================================
# UDP NETWORK CONFIGURATION
# =============================================================================

# Used by Joystick.UDP - receives light events from Octopus
config :joystick, :local_port, 4422

# Used by Joystick.UDP - sends input events to Octopus
config :joystick, :octopus_port, 4423

# Used by Joystick.UDP - Octopus host discovery via mDNS
config :joystick, :octopus_host, ~c"oldie.local"

# Customize non-Elixir parts of the firmware. See
# https://hexdocs.pm/nerves/advanced-configuration.html for details.

config :nerves, :firmware,
  rootfs_overlay: "rootfs_overlay",
  fwup_conf: "config/fwup.conf"

# Set the SOURCE_DATE_EPOCH date for reproducible builds.
# See https://reproducible-builds.org/docs/source-date-epoch/ for more information

config :nerves, source_date_epoch: "1686916824"

config :nerves_leds, names: [green: "ACT", red: "PWR"]

if Mix.target() == :host do
  import_config "host.exs"
else
  import_config "target.exs"
end
