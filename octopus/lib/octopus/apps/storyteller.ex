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

  def init(_) do
    {:ok, story} = Story.load("baumhumor")
    {[first_line], lines} = Enum.split(story.lines, 1)
    line = first_line.text |> String.split(" ", trim: true) |> Enum.map(&String.split(&1, ""))

    state = %State{
      buffer: "",
      line: line,
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

    state = %State{state | pause: max(state.pause - delta, 0)}

    tick(state)
  end

  defp next_letter(%State{line: [[letter | word] | rest]} = state) do
    Logger.debug("next letter: #{letter}")

    %State{
      state
      | pause: param(:letter_duration_ms, 100),
        line: [word | rest],
        buffer: state.buffer <> letter
    }
  end

  defp next_word(%State{line: [[] | rest]} = state) do
    Logger.debug("next word")

    %State{
      state
      | pause: param(:word_duration_ms, 500),
        line: rest,
        buffer: state.buffer <> " "
    }
  end

  defp next_line(%State{lines: []} = state) do
    Logger.debug("end of story")
    %State{state | pause: param(:end_duration_ms, 3000), line: nil, clear_buffer: true}
  end

  defp next_line(%State{lines: [line | rest]} = state) do
    Logger.debug("next line")
    line = line.text |> String.split(" ", trim: true) |> Enum.map(&String.split(&1, ""))

    %State{
      state
      | pause: param(:line_duration_ms, 1000),
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
        [] -> next_line(state)
        [[] | []] -> next_line(state)
        [[] | _] -> next_word(state)
        _ -> next_letter(state)
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
