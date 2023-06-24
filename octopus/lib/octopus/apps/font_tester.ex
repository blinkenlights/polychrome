defmodule Octopus.Apps.FontTester do
  use Octopus.App
  require Logger

  alias Octopus.Font
  alias Octopus.Protobuf.{Frame, InputEvent}

  defmodule State do
    defstruct [:index, :variant, :current_font, :text, :easing_interval]
  end

  @fonts Font.list_available() |> Enum.sort()
  @max_index Enum.count(@fonts) - 1

  @text "    DETLEF"

  def name(), do: "Font Tester"

  def init(_args) do
    state = %State{text: @text}
    state = set_font(@max_index, state)
    send(self(), :tick)

    {:ok, state}
  end

  def config_schema() do
    %{
      text: {"Text", :string, %{default: @text}},
      easing: {"Easing Interval", :int, %{default: 1000, min: 0, max: 3000}}
    }
  end

  def get_config(%State{} = state) do
    %{
      text: state.text,
      easing: state.easing_interval
    }
  end

  def handle_config(%{text: text, easing: easing}, %State{} = state) do
    {:reply, %{text: text}, %State{state | text: text, easing_interval: easing}}
  end

  def handle_info(:tick, %State{current_font: %Font{} = font} = state) do
    %Font.Variant{palette: palette} = Enum.at(font.variants, state.variant)

    data =
      state.text
      |> String.to_charlist()
      |> Enum.map(&Font.render_char(font, &1, state.variant))
      |> Enum.map(fn {data, _pallete} -> data end)
      |> List.flatten()

    %Frame{
      data: data,
      palette: palette,
      easing_interval: 2000
    }
    |> send_frame()

    :timer.send_after(100, self(), :tick)

    {:noreply, state}
  end

  def handle_input(%InputEvent{type: :BUTTON_1, value: 1}, state) do
    {:noreply, prev_font(state)}
  end

  def handle_input(%InputEvent{type: :BUTTON_2, value: 1}, state) do
    {:noreply, next_font(state)}
  end

  def handle_input(%InputEvent{type: :BUTTON_10, value: 1}, state) do
    {:noreply, next_variant(state)}
  end

  def handle_input(_input_event, state) do
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
    case Enum.count(font.variants) do
      n when variant + 1 >= n -> %State{state | variant: 0}
      _ -> %State{state | variant: variant + 1}
    end
  end
end
