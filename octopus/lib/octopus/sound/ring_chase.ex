defmodule Octopus.Sound.RingChase do
  @moduledoc """
  The first audiovisual scene: you hear the picture travel.

  A probe sits at the centre of every panel. Whenever the formula there rises
  through zero — the crest of a wave passing that panel — the speaker at *that*
  panel plays a short note. A pattern moving around the ring is heard moving
  around the ring, at the same speed and in the same direction, because both
  come from the same function.

  Nothing here decides musical time; the picture does. Change the formula and
  the rhythm changes with it, without touching a single sound parameter.

      Octopus.Sound.ring_chase(true)
  """

  use GenServer

  alias Octopus.Sound.{Engine, Probes}

  # Minimum rise per frame at the crossing. The value *at* a crossing is always
  # near zero — that is what a crossing is — so the gate has to be the steepness
  # of the wave, not its height. 0.01 per frame at 30 fps lets a wave through
  # that takes about ten seconds for a turn, and holds back a pattern that only
  # trembles around zero.
  @default_min_rise 0.002
  @default_min_interval_ms 60
  # Probes arrive on the render tick, so a crossing is only known to the
  # nearest frame — and a frame is 33 ms, which is exactly the amount of
  # stumble the ear hears in an otherwise even chase. The crossing time is
  # therefore interpolated between the two frames and the note scheduled a
  # constant step into the future, where the engine can place it precisely.
  # The cost is a fixed offset against the picture, which is what the AV
  # offset is for; the gain is a rhythm that does not wobble.
  @default_latency_ms 80
  # D dorian, seven notes without repeating the octave — with the octave in the
  # scale, the eighth panel would land on the same pitch as the first one an
  # octave up, and two panels sharing a pitch defeats the point.
  @default_scale [62, 64, 65, 67, 69, 71, 72]

  # -- API ------------------------------------------------------------------

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Switches the chase on or off."
  def enable(on?) when is_boolean(on?), do: GenServer.call(__MODULE__, {:enable, on?})

  def enabled?, do: GenServer.call(__MODULE__, :enabled?)

  @doc "Current settings, for the studio and the matrix."
  def state, do: GenServer.call(__MODULE__, :state)

  @doc "Adjusts `:min_rise`, `:synth`, `:duration_ms`, `:scale`, `:min_interval_ms`, `:latency_ms`."
  def configure(opts) when is_list(opts), do: GenServer.call(__MODULE__, {:configure, opts})

  @doc """
  Panels whose value rose through zero between two frames, with how steeply.

  Rising edges only: a falling edge is the same wave leaving, and sounding it
  would double every pass. `min_rise` gates on the steepness of the crossing —
  see `@default_min_rise` for why height would be the wrong measure.

  Returns `{panel_index, rise}` pairs, because the steepness is also what the
  note is played with.
  """
  @spec crossings([float()], [float()], float()) :: [{non_neg_integer(), float()}]
  def crossings(previous, current, min_rise) do
    previous
    |> Enum.zip(current)
    |> Enum.with_index()
    |> Enum.filter(fn {{before, now}, _index} ->
      before <= 0.0 and now > 0.0 and now - before >= min_rise
    end)
    |> Enum.map(fn {{before, now}, index} -> {index, now - before} end)
  end

  # -- Server ---------------------------------------------------------------

  @impl true
  def init(opts) do
    {:ok,
     %{
       enabled?: Keyword.get(opts, :enabled, false),
       min_rise: Keyword.get(opts, :min_rise, @default_min_rise),
       min_interval_ms: Keyword.get(opts, :min_interval_ms, @default_min_interval_ms),
       latency_ms: Keyword.get(opts, :latency_ms, @default_latency_ms),
       synth: Keyword.get(opts, :synth, "pc_ping"),
       duration_ms: Keyword.get(opts, :duration_ms, 400),
       scale: Keyword.get(opts, :scale, @default_scale),
       previous: [],
       previous_at: nil,
       last_trigger: %{}
     }
     |> subscription()}
  end

  @impl true
  def handle_call({:enable, on?}, _from, state) do
    {:reply, :ok, subscription(%{state | enabled?: on?, previous: [], previous_at: nil})}
  end

  def handle_call(:enabled?, _from, state), do: {:reply, state.enabled?, state}

  def handle_call(:state, _from, state),
    do: {:reply, Map.drop(state, [:previous, :last_trigger]), state}

  def handle_call({:configure, opts}, _from, state) do
    state = Enum.reduce(opts, state, fn {key, value}, state -> Map.replace(state, key, value) end)
    {:reply, :ok, state}
  end

  @impl true
  # Unsubscribing is not instant — a frame already in flight must not sound.
  def handle_info({:pixel_probes, _reading}, %{enabled?: false} = state), do: {:noreply, state}

  def handle_info({:pixel_probes, %{values: values, at_ms: at_ms}}, state) do
    {:noreply,
     state
     |> trigger(values, at_ms)
     |> Map.merge(%{previous: values, previous_at: at_ms})}
  end

  def handle_info(_message, state), do: {:noreply, state}

  # -- Internals ------------------------------------------------------------

  defp trigger(%{previous: []} = state, _values, _at_ms), do: state

  defp trigger(state, values, at_ms) do
    state.previous
    |> crossings(values, state.min_rise)
    |> Enum.reduce(state, fn {index, rise}, state ->
      before = Enum.at(state.previous, index)
      now = Enum.at(values, index)
      at = crossing_time(state, before, now, at_ms)

      maybe_play(state, index, rise, at, at_ms)
    end)
  end

  @doc """
  When the value actually passed zero, between the two frames it was seen in.

  Linear between the two samples: for a wave that is smooth over 33 ms — and
  every wave worth listening to is — this is accurate to well under a
  millisecond, and it is the difference between an even chase and a stumbling
  one.
  """
  @spec crossing_fraction(float(), float()) :: float()
  def crossing_fraction(before, now) when now > before, do: -before / (now - before)
  def crossing_fraction(_before, _now), do: 1.0

  defp crossing_time(%{previous_at: nil} = state, _before, _now, at_ms),
    do: at_ms + state.latency_ms

  defp crossing_time(state, before, now, at_ms) do
    fraction = crossing_fraction(before, now)
    frame_ms = at_ms - state.previous_at

    round(state.previous_at + fraction * frame_ms) + state.latency_ms
  end

  # Monotonic time is signed and starts far below zero, so "never triggered"
  # has to be its own case rather than a very small number.
  defp maybe_play(state, index, rise, at_ms, seen_at) do
    case Map.get(state.last_trigger, index) do
      last when is_integer(last) and seen_at - last < state.min_interval_ms ->
        state

      _never_or_long_enough_ago ->
        play(state, index, rise, at_ms, seen_at)
    end
  end

  defp play(state, index, rise, at_ms, seen_at) do
    Engine.note(%{
      channel: index + 1,
      note: note_for(state.scale, index),
      velocity: velocity(rise),
      duration_ms: state.duration_ms,
      synth: state.synth,
      at_ms: at_ms
    })

    %{state | last_trigger: Map.put(state.last_trigger, index, seen_at)}
  end

  @doc """
  Pitch for a panel: the scale, rising by an octave each time it runs out.

  Wrapping the scale plainly would give two panels the same pitch — with
  twelve panels and eight steps, panel 1 and panel 9 — and two identical notes
  sounding at the same instant interfere, which the ear reads as a smeared
  attack rather than as a chord.
  """
  @spec note_for([integer()], non_neg_integer()) :: integer()
  def note_for(scale, index) do
    size = length(scale)
    Enum.at(scale, rem(index, size)) + 12 * div(index, size)
  end

  # A steep crossing means a fast wave — let it hit harder than a slow one.
  defp velocity(rise), do: min(0.3 + rise * 6, 0.95)

  defp subscription(%{enabled?: true} = state) do
    Probes.subscribe()
    state
  end

  defp subscription(state) do
    Probes.unsubscribe()
    state
  end
end
