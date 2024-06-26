defmodule Octopus.Apps.StoryTeller do
  use Octopus.App, category: :animation
  use Octopus.Params, prefix: :text

  alias Octopus.Canvas
  alias Octopus.Font
  alias Octopus.Story

  @fps 60
  @frame_time_ms trunc(1000 / @fps)

  defmodule State do
    @enforce_keys [:font, :canvas, :line, :lines, :duration, :fade_in]
    defstruct [:font, :canvas, :line, :lines, :duration, :fade_in]
  end

  def name(), do: "Storyteller"

  def init(_) do
    {:ok, story} = Story.load("baumhumor")
    first_line = Enum.at(story.lines, 0)

    state = %State{
      line: first_line,
      lines: story.lines,
      duration: param(:line_duration_ms, 1000) + first_line.duration,
      fade_in: 0,
      font: Font.load("ddp-DoDonPachi (Cave)"),
      canvas: Canvas.new(8 * 10, 8)
    }

    Process.send_after(self(), :tick, @frame_time_ms)

    {:ok, state}
  end

  def handle_info(:tick, state) do
    Process.send_after(self(), :tick, @frame_time_ms)
    delta = trunc(@frame_time_ms * param(:time_scale, 1.0))
    tick(state, delta)
  end

  def tick(%State{duration: duration, lines: [next | rest]} = state, _delta)
      when duration <= 0 do
    state = %State{
      state
      | duration: param(:line_duration_ms, 1000) + next.duration,
        fade_in: 0,
        line: next,
        lines: rest
    }

    draw(state)
    {:noreply, state}
  end

  def tick(%State{duration: duration, lines: [_]} = state, _delta) when duration <= 0 do
    state = %State{state | duration: 0, fade_in: 0, lines: []}
    draw(state)
    {:noreply, state}
  end

  def tick(%State{duration: duration} = state, delta) do
    state =
      state
      |> Map.put(:duration, duration - delta)
      |> Map.put(:fade_in, state.fade_in + delta)

    draw(state)
    {:noreply, state}
  end

  def draw(%State{lines: [line | _]} = state) do
    fade_in_map =
      for i <- 0..9, y <- 0..7, x <- 0..7, into: %{} do
        x = x + i * 8
        {{x, y}, x * param(:fade_in_line_ms, 500) / (8 * 10)}
      end

    offset_x = div(10 - String.length(line.text), 2) * 8

    canvas =
      state.canvas
      |> Canvas.clear()
      |> Canvas.rect({0, 0}, {87, 7}, {0, 0, 0})

    variant =
      cond do
        Enum.member?(line.options, :direct_speech) -> 1
        true -> 0
      end

    canvas =
      Canvas.put_string(canvas, {offset_x, 0}, line.text, state.font, variant)

    pixels =
      canvas.pixels
      |> Map.filter(fn {{x, y}, _color} ->
        state.fade_in >= Map.get(fade_in_map, {x, y}, :infinity)
      end)

    canvas = %Canvas{canvas | pixels: pixels}

    canvas |> Canvas.to_frame() |> send_frame()
  end
end
