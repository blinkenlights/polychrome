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
  @default_min_rise 0.01
  @default_min_interval_ms 60
  # D dorian: no leading tone, so any order of these still sounds settled.
  @default_scale [62, 64, 65, 67, 69, 71, 72, 74]

  # -- API ------------------------------------------------------------------

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Switches the chase on or off."
  def enable(on?) when is_boolean(on?), do: GenServer.call(__MODULE__, {:enable, on?})

  def enabled?, do: GenServer.call(__MODULE__, :enabled?)

  @doc "Current settings, for the studio and the matrix."
  def state, do: GenServer.call(__MODULE__, :state)

  @doc "Adjusts `:min_rise`, `:synth`, `:duration_ms`, `:scale`, `:min_interval_ms`."
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
       synth: Keyword.get(opts, :synth, "pc_ping"),
       duration_ms: Keyword.get(opts, :duration_ms, 400),
       scale: Keyword.get(opts, :scale, @default_scale),
       previous: [],
       last_trigger: %{}
     }
     |> subscription()}
  end

  @impl true
  def handle_call({:enable, on?}, _from, state) do
    {:reply, :ok, subscription(%{state | enabled?: on?, previous: []})}
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
    {:noreply, state |> trigger(values, at_ms) |> Map.put(:previous, values)}
  end

  def handle_info(_message, state), do: {:noreply, state}

  # -- Internals ------------------------------------------------------------

  defp trigger(%{previous: []} = state, _values, _at_ms), do: state

  defp trigger(state, values, at_ms) do
    state.previous
    |> crossings(values, state.min_rise)
    |> Enum.reduce(state, fn {index, rise}, state -> maybe_play(state, index, rise, at_ms) end)
  end

  # Monotonic time is signed and starts far below zero, so "never triggered"
  # has to be its own case rather than a very small number.
  defp maybe_play(state, index, rise, at_ms) do
    case Map.get(state.last_trigger, index) do
      last when is_integer(last) and at_ms - last < state.min_interval_ms ->
        state

      _never_or_long_enough_ago ->
        play(state, index, rise, at_ms)
    end
  end

  defp play(state, index, rise, at_ms) do
    Engine.note(%{
      channel: index + 1,
      note: Enum.at(state.scale, rem(index, length(state.scale))),
      velocity: velocity(rise),
      duration_ms: state.duration_ms,
      synth: state.synth,
      at_ms: at_ms
    })

    %{state | last_trigger: Map.put(state.last_trigger, index, at_ms)}
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
