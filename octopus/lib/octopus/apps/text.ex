defmodule Octopus.Apps.Text do
  use Octopus.App, category: :animation
  require Logger

  alias Octopus.Canvas
  alias Octopus.Font

  defmodule State do
    defstruct [:text, :variant, :font, :animation, :easing_interval]
  end

  def name(), do: "Text"

  def init(config) do
    state = struct(State, config)
    send(self(), :tick)

    {:ok, state}
  end

  def config_schema() do
    %{
      text: {"Text", :string, %{default: "POLYCHROME"}},
      font: {"Font", :string, %{default: "ddp-DoDonPachi (Cave)"}},
      variant: {"Variant", :int, %{default: 0}},
      easing_interval: {"Easing Interval", :int, %{default: 500, min: 0, max: 3000}}
    }
  end

  def get_config(%State{} = state) do
    Map.take(state, [:text, :font, :variant, :easing_interval])
  end

  def handle_config(config, %State{} = state) do
    {:noreply, Map.merge(state, config)}
  end

  def handle_info(:tick, %State{} = state) do
    font_renderer = Font.load(state.font)

    state.text
    |> String.to_charlist()
    |> Enum.map(&Font.draw_char(font_renderer, &1, state.variant, Canvas.new(8, 8)))
    |> Enum.reverse()
    |> Enum.reduce(&Canvas.join/2)
    |> Canvas.to_frame()
    |> send_frame()

    :timer.send_after(100, self(), :tick)

    {:noreply, state}
  end
end
