import Config

# config :octopus, Octopus.Repo,
#   database: Path.expand("../octopus_test.db", Path.dirname(__ENV__.file)),
#   pool_size: 5,
#   stacktrace: true

config :octopus, Octopus.Repo,
  database: "octopus_test.db",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :octopus, OctopusWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "GPsqaLYP3ua3vzfYDZ66FLNCEOWWjwSKhAQVgZR41PF8d/xO0SScDfsEVPbj1vhM",
  server: false

# Disable swoosh api client as it is only required for production adapters.
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Set environment for broadcaster
config :octopus, :env, :test
config :octopus, :firmware_broadcaster_local_port, 0
config :octopus, :controller_interface_port, 0
config :octopus, :osc_server_port, 0

# Nation2026 defines radar; Pixie does not. Use Pixie so tests can start radar
# children (e.g. Mock.World) in isolation without the application supervisor.
config :octopus, :installation, Octopus.Installation.Pixie
