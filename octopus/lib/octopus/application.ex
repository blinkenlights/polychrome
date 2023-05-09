defmodule Octopus.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Octopus.Broadcaster,
      Octopus.Mixer,
      {Registry, keys: :unique, name: Octopus.AppRegistry},
      Octopus.AppSupervisor
      # Octopus.Generator
      # Octopus.FontTester
      # Octopus.SpriteTester
    ]

    opts = [strategy: :one_for_one, name: Octopus.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
