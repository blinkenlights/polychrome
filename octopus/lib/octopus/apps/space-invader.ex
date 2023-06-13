defmodule Octopus.Apps.SpaceInvader do
  use Octopus.App
  require Logger

  alias Octopus.ColorPalette
  alias Octopus.Protobuf.{Frame, AudioFrame}

  defmodule State do
    defstruct [:color, :delay, :palette, :chan, :inc]
  end

  # TODO: use the new canvas module

  def name(), do: "Space Invader"

  def init(_args) do
    state = %State{
      delay: 200,
      palette: ColorPalette.load("pico-8"),
      chan: 0,
      inc: 1
    }

    send(self(), :tick)

    {:ok, state}
  end

  @max_channels 9
  # @fileUri "https://github.com/gueldenstone/MultiChannelSampler/raw/main/resources/arcade-notification.wav"
  # @fileUri "file://Users/lukas/dev/letterbox/beak/resources/space-invader/fastinvader1.wav"
  # @fileUri "file:///Users/lukas/Downloads/PlayingSoundFilesTutorial 2/Resources/cello.wav"
  @fileUri "file://test/impulse.wav"
  # @fileUri "file://Users/lukas/dev/letterbox/beak/resources/hang.wav"
  def handle_info(:tick, %State{} = state) do
    padding_left = List.duplicate(0, 64 * state.chan)
    padding_right = List.duplicate(0, 64 * (9 - state.chan))
    color = List.duplicate(3, 64)

    data = padding_left ++ color ++ padding_right

    send_frame(%Frame{data: data, palette: state.palette})

    send_frame(%AudioFrame{
      uri: @fileUri,
      channel: state.chan + 1
    })

    :timer.send_after(state.delay, self(), :tick)

    {:noreply, increment(state)}
  end

  defp increment(%State{chan: chan, inc: inc} = state) when chan >= @max_channels do
    %State{state | inc: inc * -1, chan: chan + inc * -1}
  end

  defp increment(%State{chan: chan, inc: inc} = state) when chan == 0 and inc == -1 do
    %State{state | inc: inc * -1, chan: 1}
  end

  defp increment(%State{chan: chan, inc: inc} = state) do
    %State{state | chan: chan + inc}
  end
end
