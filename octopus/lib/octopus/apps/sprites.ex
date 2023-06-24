defmodule Octopus.Apps.Sprites do
  use Octopus.App
  require Logger

  alias Octopus.{Sprite, Canvas, Transitions}

  defmodule State do
    defstruct [:indices, :canvas]
  end

  @sprite_sheet Sprite.list_sprite_sheets() |> hd()
  @animation_interval 10
  @easing_interval 150
  @new_sprite_interval 1000

  def name(), do: "Sprites"

  def init(_args) do
    indeces = Enum.map(1..10, fn _ -> Enum.random(0..255) end)

    canvas =
      indeces
      |> Enum.map(fn index -> Sprite.load(@sprite_sheet, index) end)
      |> Enum.reduce(fn sprite, acc -> Canvas.join(acc, sprite) end)

    state = %State{
      indices: indeces,
      canvas: canvas
    }

    send(self(), :next_sprites)

    {:ok, state}
  end

  def handle_info(:next_sprites, %State{} = state) do
    updated_window = Enum.random(0..9)

    next_index = Enum.random(0..255)
    current_index = Enum.at(state.indices, updated_window)
    current_sprite = Sprite.load(@sprite_sheet, current_index)
    next_sprite = Sprite.load(@sprite_sheet, next_index)
    indices = List.update_at(state.indices, updated_window, fn _ -> next_index end)
    direction = Enum.random([:left, :right, :top, :bottom])

    Transitions.push(current_sprite, next_sprite, direction: direction)
    |> Stream.map(fn window_canvas ->
      state.canvas
      |> Canvas.overlay(window_canvas, offset: {updated_window * 8, 0})
      |> Canvas.to_frame(easing_interval: @easing_interval)
    end)
    |> Stream.map(fn frame ->
      :timer.sleep(@animation_interval)
      send_frame(frame)
    end)
    |> Stream.run()

    canvas = Canvas.overlay(state.canvas, next_sprite, offset: {updated_window * 8, 0})
    state = %State{state | indices: indices, canvas: canvas}

    :timer.send_after(@new_sprite_interval, self(), :next_sprites)

    {:noreply, state}
  end
end
