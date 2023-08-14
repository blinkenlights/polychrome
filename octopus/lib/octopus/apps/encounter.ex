defmodule Octopus.Apps.Encounter do
  use Octopus.App, category: :animation
  require Logger
  alias Octopus.Canvas
  alias Octopus.Protobuf.RGBFrame
  alias Octopus.Protobuf.{SynthFrame, ControlEvent}
  alias Octopus.Protobuf.{SynthConfig, SynthAdsrConfig}

  defmodule State do
    defstruct [:notes, :config]
  end

  def name(), do: "Encounter"

  def config_schema() do
    %{}
  end

  def get_config(%State{} = state) do
  end

  def init(_args) do
    # send(self(), :test)
    {:ok, %State{}}
  end

  def play() do
    data =
      :code.priv_dir(:octopus)
      |> Path.join("midi")
      |> Path.join("encounter.json")
      |> File.read!()
      |> Jason.decode!(keys: :atoms)

    track_configs = %{
      1 =>
        {%SynthConfig{
           wave_form: :SQUARE,
           gain: 1,
           adsr_config: %SynthAdsrConfig{
             attack: 0.01,
             decay: 0,
             sustain: 1,
             release: 0.2
           },
           filter_adsr_config: %SynthAdsrConfig{
             attack: 0,
             decay: 0.1,
             sustain: 0.2,
             release: 0.4
           },
           filter_type: :LOWPASS,
           resonance: 2,
           cutoff: 5000
         }, [1, 2, 3, 4, 5]},
      3 =>
        {%SynthConfig{
           wave_form: :SAW,
           gain: 1,
           adsr_config: %SynthAdsrConfig{
             attack: 0,
             decay: 0,
             sustain: 1,
             release: 0.1
           },
           filter_adsr_config: %SynthAdsrConfig{
             attack: 0,
             decay: 0.01,
             sustain: 0.2,
             release: 0.4
           },
           filter_type: :LOWPASS,
           resonance: 3,
           cutoff: 4000
         }, [6, 7, 8, 9, 10]}
    }

    # flatten and sort notes
    sorted_notes =
      data.tracks
      |> Enum.with_index()
      |> Enum.filter(fn {_, index} -> index in Map.keys(track_configs) end)
      |> Enum.flat_map(fn {track, index} ->
        Enum.map(track.notes, fn note ->
          new_values = %{
            :time => trunc(note.time * 1000),
            :duration => trunc(note.duration * 1000),
            :track => index
          }

          Map.merge(note, new_values)
        end)
      end)
      |> Enum.sort_by(fn note ->
        note.time
      end)

    # calculate diff to next note for every note
    notes =
      sorted_notes
      |> Enum.with_index()
      |> Enum.map(fn {note, index} ->
        new_values = %{
          :diffToNextNote => Enum.at(sorted_notes, index + 1, note).time - note.time
        }

        Map.merge(note, new_values)
      end)

    # send initial config

    track_configs
    |> Enum.map(fn {_, {config, channels}} ->
      Enum.map(channels, fn channel ->
        Logger.info("config #{channel}")

        send_frame(%SynthFrame{
          event_type: :CONFIG,
          config: config,
          channel: channel,
          note: 1,
          velocity: 1,
          duration_ms: 1
        })
      end)
    end)

    pid = self()

    # we need to spwan the actual playing as a seperate thread here
    # spawn(fn ->
    Stream.map(notes, fn note ->
      {config, channel_selection} = track_configs[note.track]
      channel = random_element(channel_selection)

      send_frame(%SynthFrame{
        event_type: :NOTE_ON,
        channel: channel,
        config: config,
        duration_ms: note.duration,
        note: note.midi,
        velocity: note.velocity
      })

      spawn(fn ->
        :timer.sleep(note.duration)
        send(pid, {:NOTE_OFF, note.midi, channel})
      end)

      :timer.sleep(note.diffToNextNote)
    end)
    |> Stream.run()

    # end)
  end

  def random_element(list) do
    random_index = :rand.uniform(length(list)) - 1
    Enum.at(list, random_index)
  end

  def handle_info({:NOTE_OFF, note, channel}, state) do
    send_frame(%SynthFrame{event_type: :NOTE_OFF, note: note, channel: channel})
    {:noreply, state}
  end

  def handle_info({:NOTE_ON, note, channel, config}, state) do
    send_frame(%SynthFrame{
      event_type: :NOTE_ON,
      channel: channel,
      config: config,
      duration_ms: note.duration,
      note: note.midi,
      velocity: note.velocity
    })

    {:noreply, state}
  end

  def handle_control_event(%ControlEvent{type: :APP_SELECTED}, state) do
    Logger.info("handle control event")
    play()
    {:noreply, state}
  end
end
