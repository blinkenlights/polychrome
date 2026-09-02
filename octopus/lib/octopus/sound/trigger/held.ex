defmodule Octopus.Sound.Trigger.Held do
  @moduledoc """
  Slots that sound continuously, their loudness following the picture.

  A held slot occupies every channel its place rule names — for a drone that
  is the whole ring — and each of those voices takes its loudness from the
  formula at that panel. Where the pattern is bright, that pitch is audible;
  where it is dark, it disappears. The chord changes because the picture does.

  Only the positive half of the formula sounds. Using the absolute value would
  make every panel audible on both halves of a wave and flatten exactly the
  movement this exists to expose.

  Loudness follows a curve rather than a straight line. Measured on the ring
  with `sin(x*0.5 - t*0.3)`, the number of panels above zero barely moves with
  zoom — 7 at ×1, 4.4 at ×6 — and what changes is *which* ones: neighbours at
  low zoom, scattered at high zoom, a tight cluster against a wide voicing. A
  straight mapping fills the space between them with half-loud voices and
  muddies that difference.

  This process owns no instrument of its own. It plays whatever held slots the
  patch holds, and is silent when there are none.
  """

  use GenServer

  alias Octopus.Sound.{Engine, Patch, Pattern, Probes}

  # 1 would be a straight mapping. Higher separates loud panels from lukewarm
  # ones; much higher makes the drone gappy.
  @contour 1.8

  # -- API ------------------------------------------------------------------

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Voices currently sounding, as `{slot_id, channel}`."
  def voices, do: GenServer.call(__MODULE__, :voices)

  @doc "Amplitude for a probe reading: the positive half, curved, scaled."
  @spec amplitude(float(), float(), float()) :: float()
  def amplitude(value, gain, contour \\ @contour) do
    :math.pow(max(value, 0.0), contour) * gain
  end

  # -- Server ---------------------------------------------------------------

  @impl true
  def init(_opts) do
    Probes.subscribe()
    Patch.subscribe()

    {:ok, %{voices: %{}}, {:continue, :adopt}}
  end

  @impl true
  def handle_continue(:adopt, state) do
    {:noreply, reconcile(state, safe_pattern())}
  end

  @impl true
  def handle_call(:voices, _from, state), do: {:reply, Map.keys(state.voices), state}

  @impl true
  def handle_info({:sound_patch, %{pattern: pattern}}, state) do
    {:noreply, reconcile(state, pattern)}
  end

  def handle_info({:pixel_probes, %{values: values}}, state) do
    for {{_slot_id, channel} = id, %{gain: gain}} <- state.voices do
      value = Enum.at(values, channel - 1) || 0.0
      Engine.set_voice(id, %{amp: amplitude(value, gain)})
    end

    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    for id <- Map.keys(state.voices), do: Engine.release(id)
    :ok
  end

  # -- Internals ------------------------------------------------------------

  # Voices are started and let go by difference, not torn down and rebuilt:
  # editing an unrelated slot must not make the whole chord stutter.
  defp reconcile(state, pattern) do
    wanted = wanted_voices(pattern)

    for id <- Map.keys(state.voices), not Map.has_key?(wanted, id) do
      Engine.release(id)
    end

    for {id, voice} <- wanted, not Map.has_key?(state.voices, id) do
      Engine.voice(id, %{
        channel: voice.channel,
        note: voice.note,
        synth: voice.synth,
        amp: 0.0
      })
    end

    %{state | voices: wanted}
  end

  defp wanted_voices(pattern) do
    panels = Engine.panels()

    for slot <- Pattern.held_slots(pattern),
        channel <- Pattern.channels_for(slot, 1, 0, panels),
        into: %{} do
      {{slot.id, channel},
       %{
         channel: channel,
         note: Pattern.pitch_for(slot, channel),
         synth: slot.synth,
         gain: slot.gain
       }}
    end
  end

  defp safe_pattern do
    Patch.pattern()
  catch
    :exit, _ -> Pattern.new()
  end
end
