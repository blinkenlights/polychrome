defmodule Joystick.Application do
  use Application

  @impl true
  def start(_type, _args) do
    opts = [strategy: :one_for_one, name: Joystick.Supervisor]

    children = [
      Joystick.Monitor,
      Joystick.UDP,
      Joystick.EventHandler
    ]

    Supervisor.start_link(children, opts)
  end

  def target() do
    Application.get_env(:joystick, :target)
  end
end
