defmodule Octopus.Apps.SpritesTester do
  use Octopus.App, category: :test
  require Logger

  alias Octopus.Sprite
  alias Octopus.Events.Event.Input, as: InputEvent

  defmodule State do
    defstruct [:index]
  end

  @sprite_sheet Sprite.list_sprite_sheets() |> hd()

  def name(), do: "Sprite Tester"

  def app_init(_args) do
    # Configure display using new unified API - adjacent layout (was Canvas.to_frame())
    Octopus.App.configure_display(layout: :adjacent_panels)
    Octopus.App.subscribe_to_button_events()

    state = %State{
      index: 0
    }

    :timer.send_interval(100, :tick)

    {:ok, state}
  end

  def handle_info(:tick, %State{} = state) do
    #    IO.inspect(state.index)

    Sprite.load(@sprite_sheet, state.index)
    |> Octopus.App.update_display()

    {:noreply, state}
  end

  def handle_event(%InputEvent{type: :button, action: :press, button: 1}, state) do
    state = %State{state | index: rem(state.index + 1, 256)}
    {:noreply, state}
  end

  def handle_event(%InputEvent{type: :button, action: :press, button: 2}, state) do
    state = %State{state | index: max(state.index - 1, 0)}
    {:noreply, state}
  end

  def handle_event(%InputEvent{}, state) do
    {:noreply, state}
  end

  def handle_event(_event, state) do
    {:noreply, state}
  end
end
