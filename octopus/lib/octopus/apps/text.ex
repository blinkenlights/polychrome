defmodule Octopus.Apps.Text do
  use Octopus.App, category: :animation

  alias Octopus.Protobuf.AudioFrame
  alias Octopus.Events.Event.Lifecycle, as: LifecycleEvent
  alias Octopus.{Canvas, Font, Transitions}

  @animation_steps 150
  @animation_interval 5

  defmodule State do
    defstruct [
      :text,
      :variant,
      :font,
      :animation,
      :letter_delay,
      :click,
      :transition
    ]
  end

  def name(), do: "Text"

  def compatible?() do
    # Text app requires 8x8 panels to properly display font characters
    installation_info = Octopus.App.get_installation_info()

    # Font rendering expects 8x8 pixel panels
    installation_info.panel_width == 8 and installation_info.panel_height == 8
  end

  def app_init(config) do
    # Configure display using new unified API - adjacent layout for character joining
    # Use smooth transitions for text readability (500ms easing)
    Octopus.App.configure_display(layout: :adjacent_panels, easing_interval: 500)

    state = struct(State, config)

    {:ok, state}
  end

  def handle_event(%LifecycleEvent{type: :app_selected}, state) do
    send(self(), :tick)
    {:noreply, state}
  end

  def handle_event(_, state), do: {:noreply, state}

  def config_schema() do
    %{
      text: {"Text", :string, %{default: "POLYCHROME"}},
      font: {"Font", :string, %{default: "ddp-DoDonPachi (Cave)"}},
      letter_delay: {"Letter Delay", :int, %{default: 5, min: 1, max: 100}},
      click: {"Click", :boolean, %{default: false}},
      variant: {"Variant", :int, %{default: 0}},
      transition: {"Transition", :string, %{default: "push"}}
    }
  end

  def get_config(%State{} = state) do
    Map.take(state, [:text, :font, :variant, :letter_delay, :click, :transition])
  end

  def handle_config(config, %State{} = state) do
    {:noreply, Map.merge(state, config)}
  end

  def handle_info(:tick, %State{} = state) do
    font = Font.load(state.font)

    # Get dynamic panel dimensions
    installation_info = Octopus.App.get_installation_info()
    empty_window = Canvas.new(installation_info.panel_width, installation_info.panel_height)

    text_chars = String.to_charlist(state.text)
    max_chars = min(length(text_chars), installation_info.panel_count)

    text_chars
    # Limit to available panels
    |> Enum.take(max_chars)
    |> Enum.with_index()
    |> Enum.map(fn {char, index} ->
      final = Font.draw_char(font, char, state.variant, empty_window)

      case state.transition do
        "none" ->
          [final]

        "flipdot" ->
          padding_start = List.duplicate(empty_window, index * state.letter_delay)

          padding_start =
            if state.click do
              padding_start ++ [{empty_window, :flip_sound, index + 1}]
            else
              padding_start
            end

          padding_end = List.duplicate(final, (max_chars - 1 - index) * state.letter_delay + 1)
          transition = Transitions.flipdot(empty_window, final)
          Stream.concat([padding_start, transition, padding_end])

        "push" ->
          padding_start = List.duplicate(empty_window, index * state.letter_delay)
          padding_end = List.duplicate(final, (max_chars - 1 - index) * state.letter_delay + 1)

          padding_end =
            if state.click do
              [padding_end_head | padding_end_tail] = padding_end
              [{padding_end_head, :click, index + 1} | padding_end_tail]
            else
              padding_end
            end

          transition =
            Transitions.push(empty_window, final, direction: :top, steps: @animation_steps)

          Stream.concat([padding_start, transition, padding_end])
      end
    end)
    |> Stream.zip()
    |> Stream.map(fn
      tuple ->
        Tuple.to_list(tuple)
        |> Enum.reverse()
        |> Enum.map(fn
          {canvas, :click, channel} ->
            send_audio_event(%AudioFrame{uri: "file://ui/switch3.wav", channel: channel})
            canvas

          {canvas, :flip_sound, channel} ->
            send_audio_event(%AudioFrame{uri: "file://transition/flipdot1.wav", channel: channel})
            canvas

          canvas ->
            canvas
        end)
        |> Enum.reduce(&Canvas.join/2)
        |> Octopus.App.update_display()
    end)
    |> Stream.map(fn _canvas ->
      :timer.sleep(@animation_interval)
    end)
    |> Stream.run()

    {:noreply, state}
  end
end
