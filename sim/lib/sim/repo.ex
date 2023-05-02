defmodule Sim.Repo do
  use Ecto.Repo,
    otp_app: :sim,
    adapter: Ecto.Adapters.Postgres
end
