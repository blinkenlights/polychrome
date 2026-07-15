import Config

# Radar: config/radar.exs holds the physical deployment bindings and boot
# source mode. Logical layout comes from the installation module; the active
# deployment is selected by host OS (:linux / :macos). runtime.exs cannot use
# import_config/1, so we evaluate the file instead.
Code.eval_file(Path.join(__DIR__, "radar.exs"))

if local = System.get_env("FIRMWARE_BROADCASTER_LOCAL_PORT") do
  config :octopus, :firmware_broadcaster_local_port, String.to_integer(local)
end

# Auto-start an app after boot (runtime). Accepts a short Apps name
# (`GravityMask`) or a full module (`Octopus.Apps.GravityMask`). Optional
# mode id for apps with `mode_config/1` / presets.
if boot_app = System.get_env("BOOT_APP") || System.get_env("OCTOPUS_BOOT_APP") do
  config :octopus, :boot_app, boot_app
end

if boot_mode = System.get_env("BOOT_APP_MODE") || System.get_env("OCTOPUS_BOOT_APP_MODE") do
  config :octopus, :boot_app_mode, boot_mode
end

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/octopus start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
# if System.get_env("PHX_SERVER") do
#   config :octopus, OctopusWeb.Endpoint, server: true
# end

if config_env() == :prod do
  database_path =
    System.get_env("DATABASE_PATH") ||
      raise """
      environment variable DATABASE_PATH is missing.
      For example: /data/octopus.db
      """

  config :octopus, Octopus.Repo,
    database: database_path,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "5")

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  # When running behind a TLS-terminating reverse proxy (Caddy, Fly, etc.) set
  # PHX_URL_PORT=443 and PHX_URL_SCHEME=https so Phoenix generates correct URLs.
  url_port = String.to_integer(System.get_env("PHX_URL_PORT") || "80")
  url_scheme = System.get_env("PHX_URL_SCHEME") || "http"

  config :octopus, OctopusWeb.Endpoint,
    url: [host: host, port: url_port, scheme: url_scheme],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/plug_cowboy/Plug.Cowboy.html
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :octopus, OctopusWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your endpoint, ensuring
  # no data is ever sent via http, always redirecting to https:
  #
  #     config :octopus, OctopusWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end
