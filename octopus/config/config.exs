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
  enable_event_mode: false

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

# Network addresses configuration
config :octopus, :enable_broadcast, true
# Default broadcast, can be overridden per environment
config :octopus, :broadcast_ip, nil
config :octopus, :localhost_ip, {127, 0, 0, 1}

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

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
