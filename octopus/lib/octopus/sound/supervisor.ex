defmodule Octopus.Sound.Supervisor do
  @moduledoc """
  Supervises the sound stack: the configured engine, the transport and the
  scheduler. Started only when `config :octopus, Octopus.Sound, enabled: true`,
  so a machine without audio boots exactly as before.
  """

  use Supervisor

  alias Octopus.Sound.{Clock, Engine, Features, Matrix, Patch, Scheduler}
  alias Octopus.Sound.Trigger

  def start_link(opts), do: Supervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    config = Engine.config()

    children = [
      {Engine.module(), Keyword.get(config, :engine_opts, [])},
      {Clock, Keyword.get(config, :clock, [])},
      {Scheduler, Keyword.get(config, :scheduler, [])},
      # The patch has to exist before the triggers adopt what is in it.
      {Patch, Keyword.get(config, :patch, [])},
      {Trigger.Probe, Keyword.get(config, :probe_trigger, [])},
      {Trigger.Held, Keyword.get(config, :held_trigger, [])},
      {Features, Keyword.get(config, :features, [])},
      {Matrix, Keyword.get(config, :matrix, [])}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
