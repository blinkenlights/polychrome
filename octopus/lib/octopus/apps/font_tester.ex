defmodule Octopus.Apps.FontTester do
  use Octopus.App, category: :test
  require Logger

  alias Octopus.Canvas
  alias Octopus.Font
  alias Octopus.Events.Event.Input, as: InputEvent

  defmodule State do
    defstruct [:index, :variant, :current_font, :text, :easing_interval]
  end

  @fonts Font.list_available() |> Enum.sort()
  @max_index Enum.count(@fonts) - 1

  @text "POLYCHROME"

  def name(), do: "Font Tester"

  def app_init(_args) do
    # Configure display using new unified API - adjacent layout (was Canvas.to_frame())
    Octopus.App.configure_display(layout: :adjacent_panels)

    state = %State{text: @text}
    state = set_font(@max_index, state)
    send(self(), :tick)

    {:ok, state}
  end

  def config_schema() do
    %{
      text: {"Text", :string, %{default: @text}},
      easing_interval: {"Easing Interval", :int, %{default: 500, min: 0, max: 3000}}
    }
  end

  def get_config(%State{} = state) do
    %{
      text: state.text,
      easing_interval: state.easing_interval
    }
  end

  def handle_config(%{text: text, easing_interval: easing_interval}, %State{} = state) do
    {:noreply, %State{state | text: text, easing_interval: easing_interval}}
  end

  def handle_info(:tick, %State{current_font: %Font{} = font} = state) do
    state.text
    |> String.to_charlist()
    |> Enum.map(&Font.draw_char(font, &1, state.variant, Canvas.new(8, 8)))
    |> Enum.reverse()
    |> Enum.reduce(&Canvas.join/2)
    |> Octopus.App.update_display()

    :timer.send_after(100, self(), :tick)

    {:noreply, state}
  end

  def handle_event(%InputEvent{type: :button, action: :press, button: 1}, state) do
    {:noreply, prev_font(state)}
  end

  def handle_event(%InputEvent{type: :button, action: :press, button: 2}, state) do
    {:noreply, next_font(state)}
  end

  def handle_event(%InputEvent{type: :button, action: :press, button: 10}, state) do
    {:noreply, next_variant(state)}
  end

  def handle_event(_input_event, state) do
    {:noreply, state}
  end

  defp prev_font(%State{index: index} = state) when index == 0 do
    set_font(@max_index, state)
  end

  defp prev_font(%State{index: index} = state) do
    set_font(index - 1, state)
  end

  defp next_font(%State{index: index} = state) when index >= @max_index do
    set_font(0, state)
  end

  defp next_font(%State{index: index} = state) do
    set_font(index + 1, state)
  end

  defp set_font(index, %State{} = state) do
    font = Enum.at(@fonts, index) |> IO.inspect() |> Font.load()
    %State{state | index: index, variant: 0, current_font: font}
  end

  defp next_variant(%State{variant: variant, current_font: %Font{} = font} = state) do
    variant =
      case Enum.count(font.variants) do
        n when variant + 1 >= n -> 0
        _ -> variant + 1
      end
      |> IO.inspect()

    %State{state | variant: variant}
  end
end
