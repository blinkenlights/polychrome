defmodule Octopus.Apps.StoryTeller do
  use Octopus.App, category: :animation

  alias Octopus.Canvas
  alias Octopus.Font
  alias Octopus.Story

  defmodule State do
    @enforce_keys [:story, :font, :canvas, :line]
    defstruct [:story, :font, :canvas, :line]
  end

  def name(), do: "Storyteller"

  def init(_) do
    {:ok, story} = Story.load("baumhumor")

    state = %State{
      story: story,
      line: 0,
      font: Font.load("ddp-DoDonPachi (Cave)"),
      canvas: Canvas.new(8 * 10, 8)
    }

    Process.send_after(self(), :next_line, 50)

    {:ok, state}
  end

  def handle_info(:next_line, %State{story: story, line: line} = state)
      when line >= length(story.lines) do
    {:noreply, %State{state | line: 0}}
  end

  def handle_info(:next_line, %State{story: story, line: line} = state) do
    %{duration: duration, text: text, options: options} = Enum.at(story.lines, line)

    offset_x = div(10 - String.length(text), 2) * 8

    canvas =
      state.canvas
      |> Canvas.clear()
      |> Canvas.rect({0, 0}, {87, 7}, {0, 0, 0})

    variant =
      cond do
        Enum.member?(options, :direct_speech) -> 1
        true -> 0
      end

    canvas =
      Canvas.put_string(canvas, {offset_x, 0}, text, state.font, variant)

    dbg({line, text, duration, options, variant})
    IO.inspect(canvas)

    canvas |> Canvas.to_frame() |> send_frame()
    canvas |> Canvas.to_frame() |> send_frame()

    Process.send_after(self(), :next_line, duration)

    {:noreply, %State{state | line: line + 1}}
  end
end
