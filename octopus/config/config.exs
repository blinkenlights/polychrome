# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

import Config

# General application configuration

config :octopus,
  ecto_repos: [Octopus.Repo],
  generators: [binary_id: true],
  show_sim_preview: true,
  enable_kiosk_mode: true,
  button_combination_range: 1..3

# =============================================================================
# UDP NETWORK CONFIGURATION
# =============================================================================

# Used by Octopus.Apps.FrameRelay - receives frames from external sources
config :octopus, :frame_relay_port, 2342

# Used by Octopus.InputAdapter - bidirectional controller communication
config :octopus, :controller_interface_port, 4423

# Used by Octopus.Broadcaster - communicates with ESP32/hardware devices
config :octopus, :firmware_broadcaster_local_port, 4422
config :octopus, :firmware_broadcaster_remote_port, 1337

# Used by Octopus.Osc.Server - Open Sound Control for audio/visual applications
config :octopus, :osc_server_port, 8000

# Network addresses are now configured in Installation modules
# See lib/octopus/installation/*.ex files

# =============================================================================
# RADAR SENSOR CONFIGURATION
# =============================================================================
#
# HLK-LD6001A-60G human-tracking radar modules connected over a USB-to-UART
# adapter. Each entry in :sensors is one physical device. The list position
# determines the integer device_id (1, 2, ...) used in PubSub messages and in
# Octopus.Radar.subscribe/1 / topic/1.
#
# Only :port is required per sensor. Any omitted key falls back to :defaults.
# Setting :sensors to [] (or removing the entry) disables the radar layer.
config :octopus, Octopus.Radar,
  sensors: [
    [port: "/dev/tty.usbserial-0001"]
  ],
  defaults: [
    # 115_200 matches our hardware. Manual §22.1 lists 921_600 as a documented
    # default, but the same manual's host-tool example uses 115_200, and our
    # specific HLK-LD6001A-60G unit only responds at 115_200. Override per
    # sensor in the :sensors list above if a unit has been reflashed.
    baud: 115_200,
    # Device geometry in centimeters (manual §9.3)
    height_cm: 300,
    range_cm: 450,
    x_pos_cm: 450,
    x_neg_cm: -450,
    y_pos_cm: 450,
    y_neg_cm: -450,
    # Disappearance timing in 100 ms units (manual §9.4)
    moving_decisecs: 110,
    static_decisecs: 100,
    exit_decisecs: 5
  ]

# Installation configuration (compile-time setting)
config :octopus, :installation, Octopus.Installation.Nation2025

# Configures the endpoint
config :octopus, OctopusWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: OctopusWeb.ErrorHTML, json: OctopusWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Octopus.PubSub,
  live_view: [signing_salt: "TMAad18b"]

config :mdns_lite,
  hosts: :hostname,
  ttl: 120,
  # instance_name: "Polychrome",
  services: [
    %{
      id: :web_service,
      protocol: "http",
      transport: "tcp",
      port: 80
    },
    %{
      id: :osc,
      protocol: "osc",
      transport: "udp",
      # Note: Keep in sync with :osc_server_port above
      port: 8000
    }
  ]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.5",
  default: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.3.2",
  default: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Elixir's built-in JSON module for Phoenix
config :phoenix, :json_library, JSON

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
