defmodule Octopus.Apps.Tla do
  use Octopus.App, category: :animation

  alias Octopus.Transitions
  alias Octopus.Canvas
  alias Octopus.Font

  @letter_delay 50
  @easing_interval 150
  @animation_interval 10
  @animation_steps 50

  defmodule Words do
    defstruct [:words, :lookup]

    def load(path) do
      words =
        path
        |> File.read!()
        |> String.split()
        |> Enum.shuffle()
        |> Enum.take(500)
        |> Enum.map(&String.upcase/1)
        |> Enum.with_index()

      lookup =
        words
        |> Stream.map(fn {word_1, index_1} ->
          new_candidates =
            words
            |> Enum.reduce([], fn {word_2, index_2}, candidates ->
              if index_1 == index_2 do
                candidates
              else
                [{index_2, distance(word_1, word_2)} | candidates]
              end
            end)
            |> Enum.sort_by(&elem(&1, 1))
            |> Enum.map(&elem(&1, 0))
            |> Enum.take(10)

          {index_1, new_candidates}
        end)
        |> Enum.into(%{})

      %__MODULE__{words: words |> Enum.to_list() |> Enum.map(&elem(&1, 0)), lookup: lookup}
    end

    def next(%__MODULE__{words: words, lookup: lookup}, current_word, exclude \\ []) do
      current_word_index = Enum.find_index(words, &(&1 == current_word))

      lookup[current_word_index]
      |> Stream.map(&Enum.at(words, &1))
      |> Stream.reject(fn word -> word in exclude end)
      |> Enum.take(1)
      |> hd()
    end

    # computes the levenshtein distance between two strings
    defp distance(a, b) do
      do_distance(a |> String.graphemes(), b |> String.graphemes(), 0)
    end

    defp do_distance([], [], distance), do: distance

    defp do_distance([a | rest_a], [b | rest_b], distance) do
      if a == b do
        do_distance(rest_a, rest_b, distance)
      else
        do_distance(rest_a, rest_b, distance + 1)
      end
    end
  end

  def name, do: "TLA"

  def init(_) do
    path = Path.join([:code.priv_dir(:octopus), "words", "words.txt"])
    words = Words.load(path)

    current_word = Enum.random(words.words)
    font = Font.load("ddp-DoDonPachi (Cave)")

    :timer.send_interval(5000, :tick)

    {:ok,
     %{
       words: words,
       last_words: [],
       font: font,
       current_word: current_word
     }}
  end

  def handle_info(:tick, %{} = state) do
    last_words = [state.current_word | state.last_words] |> Enum.take(100)
    next_word = Words.next(state.words, state.current_word, last_words)

    state.current_word
    |> dbg()
    |> String.graphemes()
    |> Enum.zip(String.graphemes(next_word))
    |> Enum.with_index()
    |> Enum.map(fn
      # {{old_char, old_char}, _index} ->
      #   old_canvas = Canvas.new(8, 8) |> Canvas.put_string({0, 0}, old_char, state.font)
      #   total_distance = distance(state.current_word, next_word) + @animation_steps + 1
      #   List.duplicate(old_canvas, total_distance)

      {{old_char, new_char}, index} ->
        old_canvas = Canvas.new(8, 8) |> Canvas.put_string({0, 0}, old_char, state.font)
        new_canvas = Canvas.new(8, 8) |> Canvas.put_string({0, 0}, new_char, state.font)

        distance = partial_distance(state.current_word, next_word, index)
        total_distance = distance(state.current_word, next_word)

        padding_start = List.duplicate(old_canvas, distance * @letter_delay)
        padding_end = List.duplicate(new_canvas, (total_distance - distance) * @letter_delay + 1)

        transition =
          Transitions.push(old_canvas, new_canvas,
            direction: Enum.random([:left, :right, :top, :bottom]),
            steps: @animation_steps
          )

        Stream.concat([padding_start, transition, padding_end])
    end)
    |> Stream.zip()
    |> Stream.map(fn tuple ->
      tuple
      |> Tuple.to_list()
      |> Enum.reverse()
      # audio here
      |> Enum.reduce(&Canvas.join/2)
      |> Canvas.to_frame(easing_interval: @easing_interval)
      |> send_frame()

      :timer.sleep(@animation_interval)
    end)
    |> Stream.run()

    {:noreply, %{state | last_words: last_words, current_word: next_word}}
  end

  defp partial_distance(old_word, last_word, index) do
    old_word = old_word |> String.graphemes() |> Enum.take(index - 1) |> Enum.join()
    last_word = last_word |> String.graphemes() |> Enum.take(index - 1) |> Enum.join()
    distance(old_word, last_word)
  end

  defp distance(a, b) do
    do_distance(a |> String.graphemes(), b |> String.graphemes(), 0)
  end

  defp do_distance([], [], distance), do: distance

  defp do_distance([a | rest_a], [b | rest_b], distance) do
    if a == b do
      do_distance(rest_a, rest_b, distance)
    else
      do_distance(rest_a, rest_b, distance + 1)
    end
  end
end
