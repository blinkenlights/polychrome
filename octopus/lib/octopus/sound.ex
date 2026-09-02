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

  alias Octopus.Sound.{Clock, Engine, Patch, Pattern, Scheduler}

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

  @doc "Receives `{:sound_note, note}` for every note played."
  defdelegate subscribe_notes(), to: Engine

  @doc "Built-in metronome — the audible proof that the clock is steady."
  defdelegate metronome(on?), to: Scheduler

  @doc "Sets the event source: `(step, timeline) -> [note params]`."
  defdelegate set_source(source), to: Scheduler

  @doc """
  Sets up a ring chase in the first free slot: every panel whose formula value
  rises through zero sounds a note on its own speaker. Needs a running Pixel
  Fun; no transport, because the picture is the clock.

  Returns the slot it filled, or `:full`.
  """
  def ring_chase(opts \\ []), do: fill_slot(&Pattern.as_chase/3, opts)

  @doc "Sets up a drone in the first free slot: one held voice per panel."
  def drone(opts \\ []), do: fill_slot(&Pattern.as_drone/3, opts)

  defp fill_slot(preset, opts) do
    pattern = Patch.pattern()

    case Pattern.free_slot(pattern) do
      nil -> :full
      slot_id -> Patch.update(&preset.(&1, slot_id, opts)) && slot_id
    end
  end

  @doc "The pattern that is playing."
  defdelegate pattern(), to: Patch

  @doc "Applies a function to the live pattern, e.g. `&Pattern.put_step(&1, 1, 0, 3)`."
  defdelegate update_pattern(fun), to: Patch, as: :update

  @doc "Switches between the A and B pattern."
  defdelegate switch_pattern(), to: Patch, as: :switch

  @doc """
  Everything off, and it stays off.

  Silencing the engine alone would last until the next step of the grid or the
  next crossing of a wave — a panic button that needs a second press is not
  one. So the transport stops, the instruments are switched off, and only then
  is everything that is sounding cut.
  """
  def panic do
    safely(&Clock.stop/0)
    safely(&Scheduler.clear/0)
    safely(fn -> Patch.update(&Pattern.silence/1) end)
    Engine.panic()
  end

  defp safely(fun) do
    fun.()
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
  end

  @doc "Which engine is active and what it can do."
  def engine do
    %{module: Engine.module(), capabilities: Engine.capabilities()}
  end
end
