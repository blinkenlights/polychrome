defmodule Octopus.Apps.Text do
  use Octopus.App, category: :animation
  require Logger

  alias Octopus.Protobuf.AudioFrame
  alias Octopus.{Canvas, Font, Transitions}

  @animation_steps 50
  @animation_interval 15
  @easing_interval 150

  defmodule State do
    defstruct [:text, :variant, :font, :animation, :easing_interval, :letter_delay, :click]
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
      letter_delay: {"Letter Delay", :int, %{default: 5, min: 1, max: 100}},
      click: {"Click", :boolean, %{default: false}},
      variant: {"Variant", :int, %{default: 0}},
      easing_interval: {"Easing Interval", :int, %{default: 500, min: 0, max: 3000}}
    }
  end

  def get_config(%State{} = state) do
    Map.take(state, [:text, :font, :variant, :easing_interval, :letter_delay, :click])
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
      padding_start = List.duplicate(empty_window, index * state.letter_delay)
      padding_end = List.duplicate(final, (9 - index) * state.letter_delay)

      padding_end =
        if state.click && length(padding_end) > 0 do
          [padding_end_head | padding_end_tail] = padding_end
          [{padding_end_head, :click, index + 1} | padding_end_tail]
        else
          padding_end
        end

      transition = Transitions.push(empty_window, final, direction: :top, steps: @animation_steps)
      Stream.concat([padding_start, transition, padding_end])
    end)
    |> Stream.zip()
    |> Stream.map(fn
      tuple ->
        Tuple.to_list(tuple)
        |> Enum.reverse()
        |> Enum.map(fn
          {canvas, :click, channel} ->
            send_frame(%AudioFrame{uri: "file://ui/switch3.wav", channel: channel})
            canvas

          canvas ->
            canvas
        end)
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
