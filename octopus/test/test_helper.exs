ExUnit.start()

if Process.whereis(Octopus.Repo) do
  Ecto.Adapters.SQL.Sandbox.mode(Octopus.Repo, :manual)
end
