defmodule Octopus.Sound do
  @moduledoc """
  Sound for the installation: one transport, one engine, one channel per panel.

  This is the layer the composer UI will sit on. Right now it is drivable from
  IEx, which is deliberate — the coupling between picture and sound should be
  audible before anything is built on top of it:

      iex> Octopus.Sound.note(channel: 3)
      iex> Octopus.Sound.metronome(true)
      iex> Octopus.Sound.play()
      iex> Octopus.Sound.panic()

  Channels are 1-based and mean panels.
  """

  alias Octopus.Sound.{Clock, Engine, Scheduler}

  @doc "Plays one note now, or at `:at_ms` (monotonic, see `Octopus.Sound.Time`)."
  def note(params \\ [])
  def note(params) when is_list(params), do: params |> Map.new() |> note()
  def note(params) when is_map(params), do: Engine.note(params)

  @doc "Starts the transport."
  defdelegate play(), to: Clock

  @doc "Stops the transport; the playhead stays where it is."
  defdelegate stop(), to: Clock

  defdelegate toggle(), to: Clock
  defdelegate set_bpm(bpm), to: Clock
  defdelegate seek(beats), to: Clock
  defdelegate position(), to: Clock
  defdelegate subscribe(), to: Clock

  @doc "Built-in metronome — the audible proof that the clock is steady."
  defdelegate metronome(on?), to: Scheduler

  @doc "Sets the event source: `(step, timeline) -> [note params]`."
  defdelegate set_source(source), to: Scheduler

  @doc "Everything off, right now."
  def panic do
    Scheduler.clear()
    Engine.panic()
  end

  @doc "Which engine is active and what it can do."
  def engine do
    %{module: Engine.module(), capabilities: Engine.capabilities()}
  end
end
