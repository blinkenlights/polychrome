defmodule Octopus.Apps.MidiTest do
  use Octopus.App
  require Logger

  alias Octopus.Protobuf.SynthEventType
  alias Octopus.Protobuf.SynthFrame
  alias Octopus.ColorPalette
  alias Octopus.Protobuf.{Frame, InputEvent}

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

    currentPlayTime = getPlayTime(state.note_data, state.index)
    nextPlayTime = getPlayTime(state.note_data, state.index + 1)
    :timer.send_after(nextPlayTime - currentPlayTime, self(), :NOTE_ON)

    {:noreply, %State{state | index: state.index + 1}}
  end
end
