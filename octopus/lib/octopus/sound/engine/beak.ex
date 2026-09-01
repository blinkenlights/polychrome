defmodule Octopus.Sound.Engine.Beak do
  @moduledoc """
  Backend for `beak`, the audio engine the installation already runs.

  Notes go out as `SynthFrame` protobuf over the same UDP broadcast that
  carries pixels. beak plays them when the packet arrives — there is no way to
  say *when* — so `capabilities/0` reports `:immediate` and the scheduler
  holds events back instead of sending them ahead.
  """

  @behaviour Octopus.Sound.Engine

  alias Octopus.Broadcaster
  alias Octopus.Protobuf
  alias Octopus.Protobuf.{AudioFrame, SynthAdsrConfig, SynthConfig, SynthFrame}

  # A short, dry pluck. beak has one synth voice type; the shape of a sound is
  # entirely in this config, which is why it travels with every note.
  @synth_config %SynthConfig{
    wave_form: :SQUARE,
    gain: 1,
    adsr_config: %SynthAdsrConfig{attack: 0.01, decay: 0.0, sustain: 1.0, release: 0.2},
    filter_adsr_config: %SynthAdsrConfig{attack: 0.0, decay: 0.1, sustain: 0.2, release: 0.4},
    filter_type: :LOWPASS,
    resonance: 2,
    cutoff: 5000
  }

  @impl true
  def start_link(_opts), do: Agent.start_link(fn -> nil end, name: __MODULE__)

  def child_spec(opts) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}}
  end

  @impl true
  def capabilities do
    %{scheduling: :immediate, channels: Octopus.Sound.Engine.channels()}
  end

  @impl true
  def note(%{channel: channel, note: note, velocity: velocity, duration_ms: duration}) do
    %SynthFrame{
      event_type: :NOTE_ON,
      channel: channel,
      note: trunc(note),
      velocity: velocity / 1,
      duration_ms: duration / 1,
      config: @synth_config
    }
    |> send_frame()
  end

  # beak has no handle on a sounding note, so a voice is a long note here and
  # `set_voice/2` is honestly a no-op rather than a silent approximation.
  @impl true
  def voice(id, %{channel: channel, note: note} = params) do
    :persistent_term.put({__MODULE__, :voice, id}, {channel, trunc(note)})

    %SynthFrame{
      event_type: :NOTE_ON,
      channel: channel,
      note: trunc(note),
      velocity: Map.get(params, :amp, 0.5) / 1,
      duration_ms: 0.0,
      config: @synth_config
    }
    |> send_frame()
  end

  @impl true
  def set_voice(_id, _params), do: :ok

  @impl true
  def release(id) do
    case :persistent_term.get({__MODULE__, :voice, id}, nil) do
      nil ->
        :ok

      {channel, note} ->
        :persistent_term.erase({__MODULE__, :voice, id})
        send_frame(%SynthFrame{event_type: :NOTE_OFF, channel: channel, note: note})
    end
  end

  @impl true
  def panic do
    for channel <- 1..Octopus.Sound.Engine.panels() do
      send_frame(%SynthFrame{event_type: :NOTE_OFF, channel: channel})
      send_frame(%AudioFrame{channel: channel, stop: true})
    end

    :ok
  end

  defp send_frame(frame) do
    frame
    |> Protobuf.encode()
    |> Broadcaster.send_binary()
  end
end
