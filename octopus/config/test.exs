import Config

config :octopus, Octopus.Repo,
  database: Path.expand("../octopus_test.db", Path.dirname(__ENV__.file)),
  pool_size: 5,
  stacktrace: true

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
