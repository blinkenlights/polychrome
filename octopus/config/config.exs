# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :octopus, :installation, Octopus.Installation.Nation

# config :octopus, :installation,
# screens: System.get_env("OCTOPUS_SCREENS", "10") |> String.to_integer()

config :octopus,
  ecto_repos: [Octopus.Repo],
  generators: [binary_id: true],
  broadcast: true,
  show_sim_preview: true,
  enable_event_mode: true

config :octopus, Friends.Repo,
  database: "octopus_#{Mix.env()}",
  username: "postgres",
  password: "postgres",
  hostname: "localhost"

# Configures the endpoint
config :octopus, OctopusWeb.Endpoint,
  url: [host: "localhost"],
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
      port: 8000
    }
  ]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
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
