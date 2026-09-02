defmodule Octopus.Sound.Trigger.Probe do
  @moduledoc """
  Slots the picture sets off: a note whenever what is measured at a panel
  rises through a level.

  A wave running around the ring passes each panel in turn, and each passing
  sounds the slot on the speaker under it. You hear the picture travel, at the
  same speed and in the same direction, because both come from one function.

  Three things this had to learn the hard way. **What** is measured decides
  whether a person perceives the coupling at all: the picture paints
  brightness `|value|`, so firing on the value crossing zero puts every note
  in the dark gap between two bright bands — precise, and indistinguishable
  from random to someone sitting in front of it. Brightness rising through a
  level fires as the band arrives.

  The gate is the **steepness** of the crossing, not the height at it — at a
  crossing the measured quantity is by definition at the level, so a height
  test says nothing. And the crossing time is interpolated between the two
  frames it was seen in and the note scheduled a constant step ahead: firing
  on arrival puts a frame of jitter straight into the rhythm.

  Several slots can listen at once, each with its own sound, gate and place —
  a deep pulse and a shimmer over it, from the same wave.
  """

  use GenServer

  alias Octopus.Sound.{Engine, Patch, Pattern, Probes}

  # Probes arrive on the render tick, so a crossing is only known to the
  # nearest frame. The note is placed a constant step into the future, where
  # the engine can put it precisely; the cost is a fixed offset against the
  # picture, which is what the AV offset is for.
  @default_latency_ms 80

  # -- API ------------------------------------------------------------------

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def state, do: GenServer.call(__MODULE__, :state)

  @doc "Sets how far ahead notes are scheduled; 0 fires them on arrival."
  def set_latency(ms) when is_integer(ms), do: GenServer.call(__MODULE__, {:latency, ms})

  @doc """
  Panels where the measured quantity rose through `level`, with how steeply.

  Rising edges only: a falling edge is the same band leaving, and sounding it
  would double every pass. Returns `{panel_index, rise}` pairs, because the
  steepness is also what the note is played with.
  """
  @spec crossings([float()], [float()], atom(), float(), float()) ::
          [{non_neg_integer(), float()}]
  def crossings(previous, current, quantity, level, min_rise) do
    previous
    |> Enum.zip(current)
    |> Enum.with_index()
    |> Enum.map(fn {{before, now}, index} ->
      {index, Pattern.measure(quantity, before), Pattern.measure(quantity, now)}
    end)
    |> Enum.filter(fn {_index, before, now} ->
      before <= level and now > level and now - before >= min_rise
    end)
    |> Enum.map(fn {index, before, now} -> {index, now - before} end)
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

  @doc "A steep crossing means a fast wave — let it hit harder than a slow one."
  @spec velocity(float(), float()) :: float()
  def velocity(rise, gain), do: min(0.3 + rise * 6, 0.95) * gain

  # -- Server ---------------------------------------------------------------

  @impl true
  def init(opts) do
    Probes.subscribe()
    Patch.subscribe()

    {:ok,
     %{
       latency_ms: Keyword.get(opts, :latency_ms, @default_latency_ms),
       slots: [],
       previous: [],
       previous_at: nil,
       fired: %{}
     }, {:continue, :adopt}}
  end

  @impl true
  def handle_continue(:adopt, state), do: {:noreply, %{state | slots: safe_slots()}}

  @impl true
  def handle_call(:state, _from, state), do: {:reply, Map.drop(state, [:previous]), state}

  def handle_call({:latency, ms}, _from, state), do: {:reply, :ok, %{state | latency_ms: ms}}

  @impl true
  def handle_info({:sound_patch, %{pattern: pattern}}, state) do
    {:noreply, %{state | slots: Pattern.probe_slots(pattern)}}
  end

  def handle_info({:pixel_probes, %{values: values, at_ms: at_ms}}, state) do
    {:noreply,
     state
     |> trigger(values, at_ms)
     |> Map.merge(%{previous: values, previous_at: at_ms})}
  end

  def handle_info(_message, state), do: {:noreply, state}

  # -- Internals ------------------------------------------------------------

  defp trigger(%{previous: []} = state, _values, _at_ms), do: state
  defp trigger(%{slots: []} = state, _values, _at_ms), do: state

  defp trigger(state, values, at_ms) do
    panels = Engine.panels()

    Enum.reduce(state.slots, state, fn slot, state ->
      state.previous
      |> crossings(
        values,
        slot.trigger.quantity,
        slot.trigger.level,
        slot.trigger.min_rise
      )
      |> Enum.reduce(state, fn {index, rise}, state ->
        play(state, slot, index, rise, values, at_ms, panels)
      end)
    end)
  end

  defp play(state, slot, index, rise, values, at_ms, panels) do
    key = {slot.id, index}
    last = Map.get(state.fired, key)

    if is_integer(last) and at_ms - last < slot.trigger.min_interval_ms do
      state
    else
      panel = index + 1
      quantity = slot.trigger.quantity
      level = slot.trigger.level
      # The interpolation works on the same quantity the crossing was found
      # in, shifted so the level sits at zero.
      before = Pattern.measure(quantity, Enum.at(state.previous, index)) - level
      now = Pattern.measure(quantity, Enum.at(values, index)) - level
      count = Map.get(state.fired, {:count, slot.id}, 0)

      for channel <- Pattern.channels_for(slot, panel, count, panels) do
        Engine.note(%{
          slot: slot.id,
          channel: channel,
          note: Pattern.pitch_for(slot, channel),
          velocity: velocity(rise, slot.gain),
          duration_ms: slot.duration_ms,
          synth: slot.synth,
          at_ms: crossing_time(state, before, now, at_ms)
        })
      end

      %{
        state
        | fired:
            state.fired
            |> Map.put(key, at_ms)
            |> Map.put({:count, slot.id}, count + 1)
      }
    end
  end

  defp crossing_time(%{previous_at: nil} = state, _before, _now, at_ms),
    do: at_ms + state.latency_ms

  defp crossing_time(state, before, now, at_ms) do
    fraction = crossing_fraction(before, now)
    frame_ms = at_ms - state.previous_at

    round(state.previous_at + fraction * frame_ms) + state.latency_ms
  end

  defp safe_slots do
    Patch.pattern() |> Pattern.probe_slots()
  catch
    :exit, _ -> []
  end
end
