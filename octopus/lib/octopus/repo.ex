defmodule Octopus.Repo do
  use Ecto.Repo,
    otp_app: :octopus,
    adapter: Ecto.Adapters.Postgres
end
