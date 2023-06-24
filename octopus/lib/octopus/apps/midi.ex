defmodule Octopus.Apps.MidiTest do
  use Octopus.App
  require Logger

  alias Octopus.Protobuf.SynthEventType
  alias Octopus.Protobuf.SynthFrame
  alias Octopus.ColorPalette
  alias Octopus.Protobuf.{Frame, InputEvent, RGBFrame}

  defmodule State do
    defstruct [:note_data, :index]
  end

  def name(), do: "Midi Test"

  @track_num 1

  def init(_args) do
    track =
      :code.priv_dir(:octopus)
      |> Path.join("midi")
      |> Path.join("encounter.json")
      |> File.read!()
      |> Jason.decode!()

    notes =
      Enum.at(track["tracks"], 1)["notes"]
      |> Enum.map(fn note ->
        %{
          note
          | "time" => trunc(note["time"] * 1000),
            "duration" => trunc(note["duration"] * 1000)
        }
      end)

    state = %State{
      note_data: notes,
      index: 1
    }

    playTime = getPlayTime(state.note_data, state.index)
    Logger.info("first note after: #{playTime}")
    :timer.send_after(playTime, self(), :NOTE_ON)

    {:ok, state}
  end

  def getPlayTime(note_data, index) do
    Enum.at(note_data, index)["time"]
  end

  def getDuration(note_data, index) do
    Enum.at(note_data, index)["duration"]
  end

  def getNote(note_data, index) do
    Enum.at(note_data, index)["midi"]
  end

  def handle_info(:NOTE_ON, %State{} = state) do
    note = getNote(state.note_data, state.index)
    Logger.info("Note: #{note}")

    # schedule note off event
    :timer.apply_after(
      getDuration(state.note_data, state.index),
      Octopus.App,
      :send_frame,
      %SynthFrame{
        event_type: :NOTE_OFF,
        note: note
      }
    )

    # send note on frame
    send_frame(%SynthFrame{
      event_type: :NOTE_ON,
      note: note
    })

    send_frame(%RGBFrame{
      data:
        List.duplicate(hsl_to_rgb(remap(note, 60, 100, 0, 360), 0.5, 0.5), 640)
        |> List.flatten()
        |> IO.iodata_to_binary(),
      easing_interval: 50
    })

    currentPlayTime = getPlayTime(state.note_data, state.index)
    nextPlayTime = getPlayTime(state.note_data, state.index + 1)
    :timer.send_after(nextPlayTime - currentPlayTime, self(), :NOTE_ON)

    {:noreply, %State{state | index: state.index + 1}}
  end

  def remap(value, old_min, old_max, new_min, new_max) do
    (value - old_min) / (old_max - old_min) * (new_max - new_min) + new_min
  end

  def hsl_to_rgb(h, s, l) do
    h = :math.fmod(h, 360)
    s = min(max(s, 0.0), 1.0)
    l = min(max(l, 0.0), 1.0)

    c = (1.0 - abs(2.0 * l - 1.0)) * s
    # x = c * (1.0 - abs((h / 60.0) |> (rem(2.0) - 1.0)))
    x = c * (1.0 - abs(((h / 60.0) |> :math.fmod(2.0)) - 1.0))
    m = l - c / 2.0

    {r1, g1, b1} =
      case h do
        h when h < 60.0 -> {c, x, 0.0}
        h when h < 120.0 -> {x, c, 0.0}
        h when h < 180.0 -> {0.0, c, x}
        h when h < 240.0 -> {0.0, x, c}
        h when h < 300.0 -> {x, 0.0, c}
        _ -> {c, 0.0, x}
      end

    [round((r1 + m) * 255), round((g1 + m) * 255), round((b1 + m) * 255)]
  end
end
