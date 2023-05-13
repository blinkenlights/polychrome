defmodule Octopus.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  alias Octopus.{ColorPalette, Font}

  @impl true
  def start(_type, _args) do
    children = [
      # Core
      {Phoenix.PubSub, name: Octopus.PubSub},
      Octopus.Broadcaster,
      Octopus.Mixer,
      {Registry, keys: :unique, name: Octopus.AppRegistry},
      Octopus.AppSupervisor,

      # Caches
      Supervisor.child_spec({Cachex, name: ColorPalette}, id: make_ref()),
      Supervisor.child_spec({Cachex, name: Font}, id: make_ref()),

      # WebApp
      OctopusWeb.Telemetry,
      {Finch, name: Octopus.Finch},
      OctopusWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Octopus.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    OctopusWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
