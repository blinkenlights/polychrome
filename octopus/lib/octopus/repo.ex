defmodule Octopus.Repo do
  use Ecto.Repo,
    otp_app: :octopus,
    adapter: Ecto.Adapters.SQLite3
end
