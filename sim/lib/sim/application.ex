defmodule Sim.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the Telemetry supervisor
      SimWeb.Telemetry,
      # Start the Ecto repository
      Sim.Repo,
      # Start the PubSub system
      {Phoenix.PubSub, name: Sim.PubSub},
      # Start Finch
      {Finch, name: Sim.Finch},
      # Start the Endpoint (http/https)
      SimWeb.Endpoint,
      # Start a worker by calling: Sim.Worker.start_link(arg)
      # {Sim.Worker, arg}
      {Sim.Pixels, name: Sim.Pixels}
    ]

    children =
      if Mix.env() != :test do
        children ++
          [
            {Sim.UdpServer, port: Application.get_env(:sim, :udp_port), name: Sim.UdpServer}
          ]
      else
        children
      end

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Sim.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    SimWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
