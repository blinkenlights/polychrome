defmodule Octopus.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the Telemetry supervisor
      OctopusWeb.Telemetry,
      # Start the Ecto repository
      # Octopus.Repo,
      # Start the PubSub system
      {Phoenix.PubSub, name: Octopus.PubSub},
      # Start Finch
      {Finch, name: Octopus.Finch},
      # Start the Endpoint (http/https)
      OctopusWeb.Endpoint,
      # Start a worker by calling: Octopus.Worker.start_link(arg)
      # {Octopus.Worker, arg}
      # {Octopus.Pixels, name: Octopus.Pixels},
      Octopus.Broadcaster,
      Octopus.Mixer,
      {Registry, keys: :unique, name: Octopus.AppRegistry},
      Octopus.AppSupervisor
    ]

    # children =
    #   if Mix.env() != :test do
    #     children ++
    #       [
    #         {Octopus.UdpServer,
    #          port: Application.get_env(:octopus, :udp_port), name: Octopus.UdpServer}
    #       ]
    #   else
    #     children
    #   end

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
