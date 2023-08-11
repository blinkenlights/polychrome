defmodule Octopus.Apps.Encounter do
  use Octopus.App
  require Logger
  alias Octopus.Protobuf.SynthFrame
  alias Octopus.Canvas
  alias Octopus.Protobuf.{SynthConfig, SynthAdsrConfig}

  @width 8 * 10 + 9 * 18
  @height 8

  defmodule GlobalState do
    defstruct [:channels_playing, :canvas]
  end

  defmodule TrackHandler do
    use GenServer
    require Logger

    alias Octopus.Apps.Midi.State
    alias Octopus.Protobuf.{RGBFrame, SynthFrame, SynthConfig, SynthAdsrConfig}

    defmodule State do
      defstruct [:note_data, :index, :config, :channels, :track, :supervisor_pid]
    end

    def start_link({note_data, {config, channels}, track, supervisor_pid}) do
      GenServer.start_link(__MODULE__, %State{
        note_data: note_data,
        index: 0,
        config: config,
        channels: channels,
        track: track,
        supervisor_pid: supervisor_pid
      })
    end

    def init(%State{} = state) do
      play_time = get_play_time(state.note_data, state.index)
      Logger.info("first note after: #{play_time}")
      :timer.send_after(div(play_time, 2), self(), :CONFIG)
      :timer.send_after(play_time, self(), :NOTE_ON)
      {:ok, state}
    end

    def get_play_time(note_data, index) do
      Enum.at(note_data, index)["time"]
    end

    def get_duration(note_data, index) do
      Enum.at(note_data, index)["duration"]
    end

    def get_note(note_data, index) do
      Enum.at(note_data, index)["midi"]
    end

    def handle_info(:CONFIG, %State{} = state) do
      for channel <- state.channels do
        IO.inspect(channel)

        do_send_frame(
          %SynthFrame{
            event_type: :CONFIG,
            channel: channel,
            note: 1,
            velocity: 1,
            duration_ms: 1,
            config: state.config
          },
          state
        )
      end

      {:noreply, state}
    end

    def handle_info(:NOTE_ON, %State{} = state) do
      note = get_note(state.note_data, state.index)
      Logger.info("Note: #{note}")
      duration = get_duration(state.note_data, state.index)
      channel = random_element(state.channels)
      :timer.send_after(duration, self(), {:NOTE_OFF, note, channel})

      # send note on frame
      do_send_frame(
        %SynthFrame{
          event_type: :NOTE_ON,
          channel: channel,
          note: note,
          velocity: 1,
          duration_ms: duration,
          config: state.config
        },
        state
      )

      currentPlayTime = get_play_time(state.note_data, state.index)
      nextPlayTime = get_play_time(state.note_data, state.index + 1)
      :timer.send_after(nextPlayTime - currentPlayTime, self(), :NOTE_ON)

      {:noreply, %State{state | index: state.index + 1}}
    end

    def handle_info({:NOTE_OFF, note, channel}, state) do
      # schedule note off event
      do_send_frame(
        %SynthFrame{
          event_type: :NOTE_OFF,
          note: note,
          channel: channel,
          config: state.config
        },
        state
      )

      {:noreply, state}
    end

    def do_send_frame(%SynthFrame{} = frame, %State{} = state) do
      send(state.supervisor_pid, {:send_frame, frame, state.track})
    end

    def do_send_frame({%RGBFrame{} = frame}, %State{} = state) do
      send(state.supervisor_pid, {:send_frame, frame})
    end

    def random_element(list) do
      random_index = :rand.uniform(length(list)) - 1
      Enum.at(list, random_index)
    end
  end

  # main app
  def name(), do: "Encounter"

  def config_schema() do
    %{
      program: {"Program", :string, %{default: "sin((t-x*0.01)-hypot(x%8-3.5,y-3.5))"}},
      easing_interval: {"Easing Interval", :int, %{default: 50, min: 0, max: 500}}
    }
  end

  def get_config(state) do
    %{program: state.source, easing_interval: state.easing_interval}
  end

  def init(_args) do
    :timer.send_interval((1000 / 60) |> trunc(), :tick)

    data =
      :code.priv_dir(:octopus)
      |> Path.join("midi")
      |> Path.join("encounter.json")
      |> File.read!()
      |> Jason.decode!()

    track_indices = %{
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
         }, [0, 1, 2, 3, 4]},
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
         }, [5, 6, 7, 8, 9]}
    }

    children =
      for track_index <- Map.keys(track_indices) do
        config = Map.get(track_indices, track_index)

        notes =
          Enum.at(data["tracks"], track_index)["notes"]
          |> Enum.map(fn note ->
            %{
              note
              | "time" => trunc(note["time"] * 1000),
                "duration" => trunc(note["duration"] * 1000)
            }
          end)

        Supervisor.child_spec({TrackHandler, {notes, config, track_index, self()}},
          id: :"TrackHandler_#{track_index}"
        )
      end

    opts = [strategy: :one_for_one, name: Octopus.Apps.Midi.Supervisor]
    Supervisor.start_link(children, opts)

    {:ok,
     %GlobalState{
       canvas: Canvas.new(80, 8),
       channels_playing: Map.new()
     }}
  end

  def handle_info({:send_frame, %SynthFrame{} = frame, track}, %GlobalState{} = state) do
    send_frame(frame)

    state =
      case frame.event_type do
        :NOTE_ON ->
          %{
            state
            | channels_playing:
                Map.put(state.channels_playing, frame.channel, {frame.note, track})
          }

        :NOTE_OFF ->
          %{
            state
            | channels_playing: Map.put(state.channels_playing, frame.channel, {false, track})
          }

        :CONFIG ->
          state
      end

    {:noreply, state}
  end

  def handle_info(:tick, %GlobalState{} = state) do
    state.canvas
    |> set_pixels(state.channels_playing)
    |> Canvas.to_frame()
    |> Map.put(:easing_interval, 1000)
    |> send_frame()

    {:noreply, state}
  end

  defp remap(value, old_min, old_max, new_min, new_max) do
    ((value - old_min) / (old_max - old_min) * (new_max - new_min) + new_min)
    |> round
  end

  def generate_pixel_high(canvas, note, chan) do
    offset_y = 7 - remap(note, 0, 127, 0, 7)
    offset_x = remap(chan, 0, 9, 0, 7)
    pixel_value = {128, 80, 100}

    Canvas.fill_rect(
      canvas,
      {chan * 8 + offset_x, offset_y},
      {chan * 8 + offset_x + 2, offset_y},
      pixel_value
    )
  end

  def generate_pixel_low(canvas, _, chan) do
    pixel_value = {255, 255, 255}

    Canvas.fill_rect(
      canvas,
      {chan * 8, 0},
      {chan * 8 + 7, 7},
      pixel_value
    )
  end

  @generators %{
    1 => &Octopus.Apps.Encounter.generate_pixel_high/3,
    3 => &Octopus.Apps.Encounter.generate_pixel_low/3
  }
  defp set_pixels(canvas, channels_playing) do
    Enum.reduce(channels_playing, canvas, fn {chan, {note, track}}, acc ->
      if note do
        f = Map.get(@generators, track)
        f.(canvas, note, chan)
      else
        acc
      end
    end)
  end
end
