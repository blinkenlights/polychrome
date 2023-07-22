defmodule Octopus.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  alias Octopus.{ColorPalette, Font, Sprite, Image}

  @impl true
  def start(_type, _args) do
    children =
      [
        # Core
        OctopusWeb.Telemetry,
        {Phoenix.PubSub, name: Octopus.PubSub},
        Octopus.Broadcaster,
        Octopus.Mixer,
        {Registry, keys: :unique, name: Octopus.AppRegistry},
        Octopus.AppSupervisor,
        Octopus.InputAdapter,

        # Caches
        Supervisor.child_spec({Cachex, name: ColorPalette}, id: make_ref()),
        Supervisor.child_spec({Cachex, name: Font}, id: make_ref()),
        Supervisor.child_spec({Cachex, name: Sprite}, id: make_ref()),
        Supervisor.child_spec({Cachex, name: Image}, id: make_ref()),

        # WebApp
        {Finch, name: Octopus.Finch},
        OctopusWeb.Endpoint
      ] ++
        case System.get_env("TELEGRAM_BOT_SECRET") do
          nil -> []
          telegram_bot_secret -> [{Octopus.TelegramBot, bot_key: telegram_bot_secret}]
        end

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
