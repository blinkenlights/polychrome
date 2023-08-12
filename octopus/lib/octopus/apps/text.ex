defmodule Octopus.Apps.Text do
  use Octopus.App, category: :animation
  require Logger

  alias Octopus.{Canvas, Font, Transitions}

  @animation_steps 50
  @animation_interval 15
  @letter_delay 5
  @easing_interval 500

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
    font = Font.load(state.font)

    empty_window = Canvas.new(8, 8)

    state.text
    |> String.to_charlist()
    |> Enum.with_index()
    |> Enum.map(fn {char, index} ->
      final = Font.draw_char(font, char, state.variant, empty_window)
      padding_start = List.duplicate(empty_window, index * @letter_delay)
      padding_end = List.duplicate(final, (9 - index) * @letter_delay)
      transition = Transitions.push(empty_window, final, direction: :top, steps: @animation_steps)
      Stream.concat([padding_start, transition, padding_end])
    end)
    |> Stream.zip()
    |> Stream.map(fn tuple ->
      Tuple.to_list(tuple)
      |> Enum.reverse()
      |> Enum.reduce(&Canvas.join/2)
      |> Canvas.to_frame(easing_interval: @easing_interval)
    end)
    |> Stream.map(fn frame ->
      :timer.sleep(@animation_interval)
      send_frame(frame)
    end)
    |> Stream.run()

    {:noreply, state}
  end
end
