defmodule Octopus.Apps.FontTester do
  use Octopus.App
  require Logger

  alias Octopus.Font
  alias Octopus.Protobuf.{Frame, InputEvent}

  defmodule State do
    defstruct [:index, :variant, :current_font]
  end

  @fonts Font.list_available() |> Enum.sort()
  @max_index Enum.count(@fonts) - 1

  @text "MILDENBERG"

  def name(), do: "Font Tester"

  def init(_args) do
    state = set_font(@max_index)

    send(self(), :tick)

    {:ok, state}
  end

  def handle_info(:tick, %State{current_font: %Font{} = font} = state) do
    %Font.Variant{palette: palette} = Enum.at(font.variants, state.variant)

    data =
      @text
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

  def handle_input(%InputEvent{type: :BUTTON, value: 1}, state) do
    {:noreply, prev_font(state)}
  end

  def handle_input(%InputEvent{type: :BUTTON, value: 2}, state) do
    {:noreply, next_font(state)}
  end

  def handle_input(%InputEvent{type: :BUTTON, value: 0}, state) do
    {:noreply, next_variant(state)}
  end

  def handle_input(_input_event, state) do
    {:noreply, state}
  end

  defp prev_font(%State{index: index}) when index == 0 do
    set_font(@max_index)
  end

  defp prev_font(%State{index: index}) do
    set_font(index - 1)
  end

  defp next_font(%State{index: index}) when index >= @max_index do
    set_font(0)
  end

  defp next_font(%State{index: index}) do
    set_font(index + 1)
  end

  defp set_font(index) do
    font = Enum.at(@fonts, index) |> IO.inspect() |> Font.load()
    %State{index: index, variant: 0, current_font: font}
  end

  defp next_variant(%State{variant: variant, current_font: %Font{} = font} = state) do
    case Enum.count(font.variants) do
      n when variant + 1 >= n -> %State{state | variant: 0}
      _ -> %State{state | variant: variant + 1}
    end
  end
end
