defmodule Octopus.Apps.StoryTeller do
  use Octopus.App, category: :animation
  use Octopus.Params, prefix: :text

  require Logger

  alias Octopus.Canvas
  alias Octopus.Font
  alias Octopus.Story

  @fps 60
  @frame_time_ms trunc(1000 / @fps)

  defmodule State do
    @derive {Inspect, only: [:line, :lines, :pause, :buffer, :clear_buffer]}
    @keys [
      :font,
      :canvas,
      :line,
      :lines,
      :pause,
      :fade_in,
      :buffer,
      :clear_buffer
    ]
    @enforce_keys @keys
    defstruct @keys
  end

  def name(), do: "Storyteller"

  def init(config) do
    {:ok, story} =
      case config do
        %{story: story} -> Story.load(story)
        %{text: text} -> {:ok, Story.parse(text)}
        _ -> Story.load("baumhumor")
      end

    {[first_line], lines} = Enum.split(story, 1)

    state = %State{
      buffer: "",
      line: first_line,
      lines: lines,
      pause: 0,
      fade_in: 0,
      font: Font.load("BlinkenLightsRegular"),
      canvas: Canvas.new(8 * 10, 8),
      clear_buffer: false
    }

    Process.send_after(self(), :tick, @frame_time_ms)

    {:ok, state}
  end

  def handle_info(:tick, %State{} = state) do
    Process.send_after(self(), :tick, @frame_time_ms)
    delta = trunc(@frame_time_ms * param(:time_scale, 1.0))

    %State{state | pause: max(state.pause - delta, 0)}
    |> tick()
  end

  defp next_letter(%State{line: {:text, [letter | rest]}} = state) do
    Logger.debug("next letter: #{letter}")

    %State{
      state
      | pause: param(:letter_duration_ms, 100),
        line: {:text, rest},
        buffer: state.buffer <> letter
    }
  end

  defp next_word(state, pause \\ nil)

  defp next_word(%State{lines: []} = state, _pause) do
    Logger.debug("end of story")
    %State{state | pause: param(:end_duration_ms, 3000), line: nil, clear_buffer: true}
  end

  defp next_word(%State{lines: [line | rest]} = state, pause) do
    Logger.debug("next line")

    %State{
      state
      | pause: pause || param(:word_duration_ms, 500),
        line: line,
        lines: rest,
        clear_buffer: true
    }
  end

  defp tick(%State{pause: 0} = state) do
    state =
      if state.clear_buffer, do: Map.merge(state, %{buffer: "", clear_buffer: false}), else: state

    state =
      case state.line do
        {:text, [_ | _]} -> next_letter(state)
        {:text, []} -> next_word(state)
        {:pause, :short} -> next_word(state, param(:short_pause_duration_ms, 1000))
        {:pause, :long} -> next_word(state, param(:long_pause_duration_ms, 2000))
      end

    draw(state)

    {:noreply, state}
  end

  defp tick(%State{} = state) do
    draw(state)
    {:noreply, state}
  end

  def draw(%State{buffer: line} = state) do
    canvas =
      state.canvas
      |> Canvas.clear()
      |> Canvas.rect({0, 0}, {87, 7}, {0, 0, 0})

    variant = 0

    canvas =
      Canvas.put_string(canvas, {0, 0}, line, state.font, variant)

    canvas |> Canvas.to_frame() |> send_frame()
  end
end
