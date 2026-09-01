defmodule Octopus.Sound.Supervisor do
  @moduledoc """
  Supervises the sound stack: the configured engine, the transport and the
  scheduler. Started only when `config :octopus, Octopus.Sound, enabled: true`,
  so a machine without audio boots exactly as before.
  """

  use Supervisor

  alias Octopus.Sound.{Clock, Drone, Engine, Features, Matrix, Patch, RingChase, Scheduler}

  def start_link(opts), do: Supervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    config = Engine.config()

    children = [
      {Engine.module(), Keyword.get(config, :engine_opts, [])},
      {Clock, Keyword.get(config, :clock, [])},
      {Scheduler, Keyword.get(config, :scheduler, [])},
      {RingChase, Keyword.get(config, :ring_chase, [])},
      {Patch, Keyword.get(config, :patch, [])},
      {Drone, Keyword.get(config, :drone, [])},
      {Features, Keyword.get(config, :features, [])},
      {Matrix, Keyword.get(config, :matrix, [])}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
