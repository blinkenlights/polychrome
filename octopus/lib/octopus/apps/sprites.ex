defmodule Octopus.Apps.Sprites do
  use Octopus.App
  require Logger

  alias Octopus.{Sprite, Canvas, Transitions}
  alias Octopus.Protobuf.{InputEvent}

  defmodule State do
    defstruct [:transition, :index]
  end

  @sprite_sheet Sprite.list_sprite_sheets() |> hd()
  @animation_duration 1000

  def name(), do: "Sprites"

  def init(_args) do
    state = %State{index: 0}

    # :timer.send_interval(250, :tick)
    send(self(), :tick)

    {:ok, state}
  end

  def handle_info(:tick, %State{} = state) do
    state = next_sprite(state)
    :timer.send_after(2000, self(), :tick)
    {:noreply, state}
  end

  def handle_input(%InputEvent{type: :BUTTON_1, value: 1}, state) do
    {:noreply, next_sprite(state)}
  end

  def next_sprite(%State{} = state) do
    next_index = rem(state.index + 1, 256)
    current_sprite = Sprite.load(@sprite_sheet, state.index)
    next_sprite = Sprite.load(@sprite_sheet, next_index)
    # transition = Transitions.flipdot(current_sprite, next_sprite) |> IO.inspect()
    direction = Enum.random([:left, :right, :top, :bottom])
    transition = Transitions.push(current_sprite, next_sprite, direction: direction)

    animate(transition)

    %State{state | transition: transition, index: next_index}
  end

  def animate(transitions) do
    transitions
    |> Stream.map(fn canvas -> Canvas.to_frame(canvas, easing_interval: 150) end)
    |> Stream.map(fn frame ->
      :timer.sleep(10)
      send_frame(frame)
    end)
    |> Stream.run()
  end
end
