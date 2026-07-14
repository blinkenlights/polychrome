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

# =============================================================================
# RECORDING
# =============================================================================

# Records the frames the mixer sends to the LED panels into an append-only file
# that can be converted to video. Disabled by default so it has zero overhead
# and can never influence the running installation unless explicitly enabled.
config :octopus, Octopus.Recording,
  enabled: false,
  output_dir: "recordings",
  max_queue: 600,
  # Where an auto-started/default recording is written:
  #   {:file, []}                              -> local file (default)
  #   {:remote, host: "10.0.0.5", port: 7000}  -> stream to a TCP server
  sink: {:file, []},
  # gzip the recording stream (built-in :zlib, no native deps). File targets
  # gain a .gz suffix; encoders read .gz transparently. Lower gzip_level is
  # cheaper on constrained CPUs (e.g. Raspberry Pi).
  compress: false,
  gzip_level: 6

# Network addresses are now configured in Installation modules
# See lib/octopus/installation/*.ex files

# Radar (HLK-LD6001A): see config/radar.exs (loaded at runtime via runtime.exs)

# Installation configuration (compile-time setting).
# Override at build time via the INSTALLATION_MODULE env var (see Dockerfile ARG).
config :octopus,
       :installation,
       System.get_env("INSTALLATION_MODULE", "Octopus.Installation.Nation2026")
       |> then(&Module.concat([&1]))

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
  ],
  sim3d: [
    args:
      ~w(js/app_sim3d.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ],
  sim3daframe: [
    args:
      ~w(js/app_sim3daframe.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
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
