defmodule Octopus.Apps.Encounter do
  use Octopus.App, category: :game
  require Logger
  alias Octopus.Canvas
  alias Octopus.Protobuf.{SynthFrame, SynthConfig, SynthAdsrConfig}
  alias Octopus.Events.Event.Lifecycle, as: LifecycleEvent

  defmodule State do
    defstruct [:notes, :config, :canvas, :display_info]
  end

  def name(), do: "Encounter"

  def config_schema() do
    %{}
  end

  def get_config(%State{} = _state) do
    %{}
  end

  def app_init(_args) do
    # Configure display using new unified API - adjacent layout (was Canvas.to_frame())
    Octopus.App.configure_display(layout: :adjacent_panels)

    # Get dynamic display dimensions
    display_info = Octopus.App.get_display_info()
    canvas = Canvas.new(display_info.width, display_info.height)

    {:ok, %State{canvas: canvas, display_info: display_info}}
  end

  def play(%State{display_info: display_info} = _state) do
    pid = self()

    data =
      :code.priv_dir(:octopus)
      |> Path.join("midi")
      |> Path.join("encounter.json")
      |> File.read!()
      |> JSON.decode!()
      |> atomize_keys()

    # Dynamically assign channels based on available panels
    panel_count = display_info.num_panels
    half_panels = div(panel_count, 2)

    # Split channels across two tracks based on panel count
    track1_channels = Enum.to_list(1..half_panels)
    track2_channels = Enum.to_list((half_panels + 1)..panel_count)

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
         }, track1_channels},
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
         }, track2_channels}
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

        send_synth_event(%SynthFrame{
          event_type: :CONFIG,
          config: config,
          channel: channel,
          note: 1,
          velocity: 1,
          duration_ms: 1
        })
      end)
    end)

    # clear canvas using new unified API
    Canvas.new(display_info.width, display_info.height) |> Octopus.App.update_display()

    Task.start_link(fn ->
      Stream.map(notes, fn note ->
        {config, channel_selection} = track_configs[note.track]
        channel = random_element(channel_selection)

        send_synth_event(
          %SynthFrame{
            event_type: :NOTE_ON,
            channel: channel,
            config: config,
            duration_ms: note.duration,
            note: note.midi,
            velocity: note.velocity
          },
          pid
        )

        send(pid, {:NOTE_ON, channel, note.midi})

        Task.start_link(fn ->
          :timer.sleep(note.duration)

          send_synth_event(
            %SynthFrame{event_type: :NOTE_OFF, note: note.midi, channel: channel},
            pid
          )

          send(pid, {:NOTE_OFF, channel, note.midi})
        end)

        :timer.sleep(note.diffToNextNote)
      end)
      |> Stream.run()
    end)
  end

  def random_element(list) do
    random_index = :rand.uniform(length(list)) - 1
    Enum.at(list, random_index)
  end

  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {String.to_atom(k), atomize_keys(v)} end)
  end

  defp atomize_keys(list) when is_list(list), do: Enum.map(list, &atomize_keys/1)
  defp atomize_keys(value), do: value

  def handle_info({:NOTE_ON, channel, note}, %State{} = state) do
    %Chameleon.RGB{r: r, g: g, b: b} =
      Chameleon.HSV.new(round((note - 20) / 100 * 360), 100, 100)
      |> Chameleon.convert(Chameleon.RGB)

    # Calculate panel position dynamically based on panel dimensions
    panel_width = state.display_info.panel_width
    panel_height = state.display_info.panel_height
    top_left = {(channel - 1) * panel_width, 0}
    bottom_right = {elem(top_left, 0) + panel_width - 1, panel_height - 1}

    canvas = state.canvas |> Canvas.fill_rect(top_left, bottom_right, {r, g, b})
    Octopus.App.update_display(canvas)

    {:noreply, %{state | canvas: canvas}}
  end

  def handle_info({:NOTE_OFF, channel, _note}, %State{} = state) do
    # Calculate panel position dynamically based on panel dimensions
    panel_width = state.display_info.panel_width
    panel_height = state.display_info.panel_height
    top_left = {(channel - 1) * panel_width, 0}
    bottom_right = {elem(top_left, 0) + panel_width - 1, panel_height - 1}

    canvas = state.canvas |> Canvas.clear_rect(top_left, bottom_right)
    Octopus.App.update_display(canvas)

    {:noreply, %{state | canvas: canvas}}
  end

  def handle_event(%LifecycleEvent{type: :app_selected}, state) do
    Logger.info("handle control event")
    play(state)
    {:noreply, state}
  end

  def handle_event(_event, state) do
    {:noreply, state}
  end
end
