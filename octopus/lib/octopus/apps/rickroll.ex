defmodule Octopus.Apps.Rickroll do
  use Octopus.App, category: :animation

  alias Octopus.Canvas
  alias Octopus.Protobuf.AudioFrame
  alias Octopus.Protobuf.ControlEvent
  alias Octopus.WebP

  require Logger

  def name, do: "Rickroll"

  def init(_) do
    animation = WebP.load_animation("rickroll-fullwidth")
    send(self(), :tick)
    {:ok, %{animation: animation, index: 0}}
  end

  def handle_info(:tick, %{animation: animation, index: index} = state) do
    {canvas, duration} = Enum.at(animation, index)
    canvas |> Canvas.to_frame() |> send_frame()
    index = rem(index + 1, length(animation))
    Process.send_after(self(), :tick, duration)
    {:noreply, %{state | index: index}}
  end

  def handle_control_event(%ControlEvent{type: :APP_SELECTED}, state) do
    1..10
    |> Enum.map(&%AudioFrame{uri: "file://rickroll.wav", stop: false, channel: &1})
    |> Enum.each(&send_frame/1)

    {:noreply, state}
  end

  def handle_control_event(_, state) do
    {:noreply, state}
  end
end
