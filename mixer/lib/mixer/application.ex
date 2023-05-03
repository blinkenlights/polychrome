defmodule Mixer.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Mixer.Broadcaster,
      Mixer.Generator
    ]

    opts = [strategy: :one_for_one, name: Mixer.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
