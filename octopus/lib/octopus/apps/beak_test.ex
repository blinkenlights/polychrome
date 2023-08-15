defmodule Octopus.Apps.BeakTest do
  use Octopus.App, category: :animation
  require Logger

  alias Octopus.Protobuf.{SynthFrame, SynthAdsrConfig, SynthConfig}
  alias Octopus.Canvas
  alias Octopus.Protobuf.InputEvent

  defmodule State do
    defstruct [:index, :color, :canvas]
  end

  @fps 60
  @colors [{255, 255, 255}, {255, 0, 0}, {0, 255, 0}, {255, 0, 255}]

  def name(), do: "Beak"

  @supported_buttons [
    :BUTTON_1,
    :BUTTON_2,
    :BUTTON_3,
    :BUTTON_4,
    :BUTTON_5,
    :BUTTON_6,
    :BUTTON_7,
    :BUTTON_8,
    :BUTTON_9,
    :BUTTON_10
  ]

  def init(_args) do
    state = %State{
      index: 0,
      color: 0
    }

    {:ok, %State{canvas: Canvas.new(80, 8)}}
  end

  def handle_input(%InputEvent{type: button, value: 1}, %State{} = state)
      when button in @supported_buttons do
    "BUTTON_" <> btn_number = button |> to_string()
    channel = String.to_integer(btn_number)

    send_frame(%SynthFrame{
      event_type: :NOTE_ON,
      channel: channel,
      config: %SynthConfig{
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
      },
      duration_ms: 500,
      note: 60 + channel,
      velocity: 1
    })

    top_left = {(channel - 1) * 8, 0}
    bottom_right = {elem(top_left, 0) + 7, 7}

    canvas =
      state.canvas
      |> Canvas.fill_rect(top_left, bottom_right, {255, 255, 255})

    canvas |> Canvas.to_frame() |> send_frame()
    {:noreply, %State{state | canvas: canvas}}
  end

  def handle_input(%InputEvent{type: button, value: 0}, state)
      when button in @supported_buttons do
    "BUTTON_" <> btn_number = button |> to_string()

    channel = String.to_integer(btn_number)

    top_left = {(channel - 1) * 8, 0}
    bottom_right = {elem(top_left, 0) + 7, 7}

    canvas =
      state.canvas
      |> Canvas.clear_rect(top_left, bottom_right)

    canvas |> Canvas.to_frame() |> send_frame()
    {:noreply, %State{state | canvas: canvas}}
  end

  def handle_input(_input_event, state) do
    {:noreply, state}
  end

  def handle_control_event(_event, state) do
    {:noreply, state}
  end
end
