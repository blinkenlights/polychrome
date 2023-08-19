defmodule Octopus.Apps.Tla do
  use Octopus.App, category: :animation

  alias Octopus.Canvas
  alias Octopus.Font

  defmodule Words do
    defstruct [:words, :lookup]

    def load(path) do
      words =
        path
        |> File.read!()
        |> String.split()
        |> Enum.filter(fn word -> String.length(word) == 10 end)
        |> Enum.shuffle()
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
    path = Path.join([:code.priv_dir(:octopus), "words", "500-10-letter-words.txt"])
    words = Words.load(path)
    :timer.send_interval(5000, :next_word)

    current_word = Enum.random(words.words)
    font = Font.load("ddp-DoDonPachi (Cave)")
    font_variants_count = length(font.variants)

    chars = current_word |> String.graphemes() |> Enum.map(&[{&1, {0, 0}, 0}])

    :timer.send_interval(100, :tick)

    {:ok,
     %{
       words: words,
       last_words: [],
       font: font,
       font_variants_count: font_variants_count,
       chars: chars,
       current_word: current_word
     }}
  end

  def handle_info(:tick, %{chars: chars} = state) do
    chars
    |> Enum.map(fn chars ->
      canvas = Canvas.new(8, length(chars))

      chars
      |> Enum.reduce(canvas, fn {char, offset, variant}, canvas ->
        Canvas.put_string(canvas, offset, char, state.font, variant)
      end)
      |> Canvas.cut({0, 0}, {7, 7})
    end)
    |> Enum.reverse()
    |> Enum.reduce(&Canvas.join/2)
    |> Canvas.to_frame()
    |> send_frame()

    chars =
      chars
      |> Enum.map(fn foo ->
        if length(foo) > 1 do
          Enum.map(foo, fn {char, {x, y}, variant} ->
            {char, {x, y - 1}, variant}
          end)
          |> Enum.drop_while(fn {_chars, {_, y}, _variant} -> y < -8 end)
        else
          foo
        end
      end)

    {:noreply, %{state | chars: chars}}
  end

  def handle_info(
        :next_word,
        %{
          words: words,
          current_word: current_word,
          chars: chars,
          last_words: last_words,
          font: _font
        } = state
      ) do
    last_words = [current_word | last_words] |> Enum.take(50)
    next_word = Words.next(words, current_word, last_words)

    chars =
      chars
      |> Enum.zip(String.graphemes(next_word))
      |> Enum.map(fn {chars, new_char} ->
        if Enum.any?(chars, fn {char, _offset, _variant} -> new_char == char end) do
          chars
        else
          chars ++
            [{new_char, {0, length(chars) * 9}, Enum.random([0, 1, 2, 3, 6, 7, 8, 9, 10, 11])}]
        end
      end)

    {:noreply, %{state | last_words: last_words, chars: chars, current_word: next_word}}
  end
end
