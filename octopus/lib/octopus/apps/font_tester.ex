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

  @text "AllUrBase!"

  def name(), do: "Font Tester"

  def init(_args) do
    state = %State{index: 0} |> next_font()

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
      palette: palette
    }
    |> send_frame()

    :timer.send_after(100, self(), :tick)

    {:noreply, state}
  end

  def handle_input(%InputEvent{type: :BUTTON, value: 1}, state) do
    {:noreply, next_font(state)}
  end

  def handle_input(%InputEvent{type: :BUTTON, value: 2}, state) do
    {:noreply, next_variant(state)}
  end

  def handle_input(_input_event, state) do
    {:noreply, state}
  end

  defp next_font(%State{index: index}) when index >= @max_index do
    index = 0
    font = Enum.at(@fonts, index) |> Font.load()
    %State{index: index, variant: 0, current_font: font}
  end

  defp next_font(%State{index: index}) do
    index = index + 1

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
