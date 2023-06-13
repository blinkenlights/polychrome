defmodule Octopus.Apps.BeakInteractive do
  use Octopus.App
  require Logger

  alias Octopus.ColorPalette
  alias Octopus.Protobuf.{Frame, AudioFrame, InputEvent}

  defmodule State do
    defstruct [:color, :palette, :chan]
  end

  # TODO: use the new canvas module

  def name(), do: "Beak interactive"

  def init(_args) do
    state = %State{
      palette: ColorPalette.load("pico-8"),
      chan: 0
    }

    {:ok, state}
  end

  @max_channels 9
  # @fileUri "https://github.com/gueldenstone/MultiChannelSampler/raw/main/resources/arcade-notification.wav"
  # @fileUri "file://space-invader/ufo_lowpitch.wav"
  # @fileUri "file:///Users/lukas/Downloads/PlayingSoundFilesTutorial 2/Resources/cello.wav"
  @fileUri "file://test/impulse.wav"
  # @fileUri "file://Users/lukas/dev/letterbox/beak/resources/hang.wav"

  def handle_input(%InputEvent{button: but, pressed: true}, state) do
    buttonNum =
      case but do
        :BUTTON_1 -> 1
        :BUTTON_2 -> 2
        :BUTTON_3 -> 3
        :BUTTON_4 -> 4
        :BUTTON_5 -> 5
        :BUTTON_6 -> 6
        :BUTTON_7 -> 7
        :BUTTON_8 -> 8
        :BUTTON_9 -> 9
        :BUTTON_10 -> 10
      end

    padding_left = List.duplicate(0, 64 * (buttonNum - 1))
    padding_right = List.duplicate(0, 64 * (9 - (buttonNum - 1)))
    color = List.duplicate(3, 64)

    data = padding_left ++ color ++ padding_right

    send_frame(%Frame{data: data, palette: state.palette})

    send_frame(%AudioFrame{
      uri: @fileUri,
      channel: 9
    })

    {:noreply, state}
  end
end
