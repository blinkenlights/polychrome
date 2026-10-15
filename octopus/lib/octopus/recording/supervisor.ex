defmodule Octopus.Recording.Supervisor do
  @moduledoc """
  Isolated supervision subtree for the recording subsystem.

  Started unconditionally by the application, but its children are cheap and
  idle unless a recording is active. Keeping recording under its own supervisor
  (with a `:one_for_one` strategy) guarantees that a recorder restart can never
  affect the mixer, broadcaster, or apps.
  """

  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      Octopus.Recording.PanelRecorder
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
