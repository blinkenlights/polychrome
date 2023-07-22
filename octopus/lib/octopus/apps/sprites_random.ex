defmodule Octopus.Apps.Sprites do
  use Octopus.App
  require Logger

  alias Octopus.{Sprite, Canvas, Transitions}

  defmodule State do
    defstruct [:indexes, :canvas, :screens]
  end

  @sprite_sheet "256-characters-original"
  @animation_interval 10
  @animation_steps 50
  @easing_interval 150
  @new_sprite_interval 5000

  def name(), do: "Random Sprites"

  def init(_args) do
    screens = get_screen_count()
    indexes = Enum.map(1..screens, fn _ -> Enum.random(0..255) end)

    canvas =
      indexes
      |> Enum.map(fn index -> Sprite.load(@sprite_sheet, index) end)
      |> Enum.reduce(fn sprite, acc -> Canvas.join(acc, sprite) end)

    state = %State{
      indexes: indexes,
      canvas: canvas,
      screens: screens
    }

    send(self(), :next_sprites)

    {:ok, state}
  end

  def handle_info(:next_sprites, %State{} = state) do
    updated_window = Enum.random(0..(state.screens - 1))

    next_index = Enum.random(0..255)
    current_index = Enum.at(state.indexes, updated_window)
    current_sprite = Sprite.load(@sprite_sheet, current_index)
    next_sprite = Sprite.load(@sprite_sheet, next_index)
    indexes = List.update_at(state.indexes, updated_window, fn _ -> next_index end)
    direction = Enum.random([:left, :right, :top, :bottom])

    Transitions.push(current_sprite, next_sprite, direction: direction, steps: @animation_steps)
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
    state = %State{state | indexes: indexes, canvas: canvas}

    :timer.send_after(@new_sprite_interval, self(), :next_sprites)

    {:noreply, state}
  end
end
