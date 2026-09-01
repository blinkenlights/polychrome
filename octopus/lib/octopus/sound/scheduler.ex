defmodule Octopus.Sound.Scheduler do
  @moduledoc """
  Turns musical time into notes, ahead of time.

  Every tick it looks a fixed window into the future, asks the timeline which
  steps fall inside it, and hands the resulting notes to the engine with the
  timestamp they belong to. Because the window is larger than any jitter the
  BEAM produces, timing is decided by the engine's clock, not by when this
  process happened to run.

  Engines that cannot schedule (`beak`) get their notes held back here and
  delivered just in time instead — same source, worse precision, no change
  anywhere above.

  The event source is a function `(step, timeline) -> [note]`. M1 ships a
  metronome; the step grid will be the next one.
  """

  use GenServer

  alias Octopus.Sound.{Clock, Engine, Time, Timeline}

  @tick_interval_ms 25
  @default_lookahead_ms 200
  # A gap this large means the transport was seeked, not that we fell behind.
  @resync_beats 4.0

  # -- API ------------------------------------------------------------------

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Switches the built-in metronome on or off."
  def metronome(on?) when is_boolean(on?), do: GenServer.call(__MODULE__, {:metronome, on?})

  @doc """
  Sets the event source: `(step, timeline) -> [note params]`, called once per
  step, ahead of time. Pass `nil` for silence.
  """
  def set_source(source) when is_function(source, 2) or is_nil(source),
    do: GenServer.call(__MODULE__, {:source, source})

  @doc "Drops everything scheduled but not yet sent."
  def clear, do: GenServer.call(__MODULE__, :clear)

  @doc "A click on channel 1, accented on the first beat of the bar."
  def metronome_source(%{beats: beats}, %Timeline{} = timeline) do
    if beats == Float.round(beats) do
      bar_start? = :math.fmod(beats, timeline.beats_per_bar) == 0.0

      [
        %{
          channel: 1,
          note: if(bar_start?, do: 84, else: 72),
          velocity: if(bar_start?, do: 0.9, else: 0.5),
          duration_ms: 40,
          synth: "pc_click"
        }
      ]
    else
      []
    end
  end

  # -- Server ---------------------------------------------------------------

  @impl true
  def init(opts) do
    {:ok, _} = :timer.send_interval(@tick_interval_ms, :tick)

    {:ok,
     %{
       lookahead_ms: Keyword.get(opts, :lookahead_ms, lookahead_from_config()),
       source: Keyword.get(opts, :source),
       last_beats: nil,
       pending: []
     }}
  end

  @impl true
  def handle_call({:metronome, true}, _from, state),
    do: {:reply, :ok, %{state | source: &__MODULE__.metronome_source/2}}

  def handle_call({:metronome, false}, _from, state), do: {:reply, :ok, %{state | source: nil}}
  def handle_call({:source, source}, _from, state), do: {:reply, :ok, %{state | source: source}}

  def handle_call(:clear, _from, state) do
    Enum.each(state.pending, &Process.cancel_timer/1)
    {:reply, :ok, %{state | pending: []}}
  end

  @impl true
  def handle_info(:tick, %{source: nil} = state), do: {:noreply, %{state | last_beats: nil}}

  def handle_info(:tick, state) do
    timeline = Clock.timeline()

    if timeline.playing? do
      {:noreply, schedule_window(state, timeline)}
    else
      {:noreply, %{state | last_beats: nil}}
    end
  end

  def handle_info({:fire, note}, state) do
    Engine.note(note)
    {:noreply, %{state | pending: Enum.reject(state.pending, &(Process.read_timer(&1) == false))}}
  end

  def handle_info(_message, state), do: {:noreply, state}

  # -- Internals ------------------------------------------------------------

  defp schedule_window(state, timeline) do
    now = Time.now()
    horizon = Timeline.beats_at(timeline, now + state.lookahead_ms)
    from = window_start(state.last_beats, timeline, now, horizon)

    state =
      timeline
      |> Timeline.steps_between(from, horizon)
      |> Enum.reduce(state, &emit_step(&1, &2, timeline))

    %{state | last_beats: horizon}
  end

  # A missing, overtaken or far-away mark means the transport moved under us —
  # start a fresh window at the playhead instead of replaying the gap.
  defp window_start(nil, _timeline, now, _horizon), do: current_beats(now)

  defp window_start(last, timeline, now, horizon) do
    if last > horizon or horizon - last > @resync_beats do
      Timeline.beats_at(timeline, now)
    else
      last
    end
  end

  defp current_beats(now), do: Timeline.beats_at(Clock.timeline(), now)

  defp emit_step(step, state, timeline) do
    at_ms = round(Timeline.ms_at(timeline, step.beats))

    state.source.(step, timeline)
    |> Enum.reduce(state, fn note, state -> emit(Map.put(note, :at_ms, at_ms), state) end)
  end

  defp emit(note, state) do
    case Engine.capabilities() do
      %{scheduling: :timestamped} ->
        Engine.note(note)
        state

      _immediate ->
        delay = max(note.at_ms - Time.now(), 0)
        %{state | pending: [Process.send_after(self(), {:fire, note}, delay) | state.pending]}
    end
  end

  defp lookahead_from_config do
    Keyword.get(Engine.config(), :lookahead_ms, @default_lookahead_ms)
  end
end
