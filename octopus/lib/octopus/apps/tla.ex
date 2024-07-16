defmodule Octopus.Apps.Tla do
  use Octopus.App, category: :animation
  use Octopus.Params, prefix: :tla

  alias Octopus.Font
  alias Octopus.Transitions
  alias Octopus.Canvas
  alias Octopus.Animator

  require Logger

  defmodule Words do
    defstruct [:words, :lookup]

    def load(path) do
      words =
        path
        |> File.read!()
        |> String.split("\n", trim: true)
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

      candidate =
        lookup[current_word_index]
        |> Stream.map(&Enum.at(words, &1))
        |> Stream.reject(fn word -> word in exclude end)
        |> Enum.take(1)

      case candidate do
        [] -> Enum.random(words)
        [word | _] -> word
      end
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
    path = Path.join([:code.priv_dir(:octopus), "words", "nog24-256-10--letter-words.txt"])
    words = Words.load(path)
    :timer.send_after(0, :next_word)

    current_word = Enum.random(words.words)
    font = Font.load("BlinkenLightsRegular")
    font_variants_count = length(font.variants)

    {:ok, animator} = Animator.start_link(get_app_id())

    current_canvas = Canvas.new(80, 8) |> Canvas.put_string({0, 0}, current_word, font)

    transition = &Transitions.push(&1, &2, direction: :top, steps: 60, separation: 3)

    Animator.start_animation(animator, current_canvas, {0, 0}, transition, 1500)

    {:ok,
     %{
       words: words,
       last_words: [],
       font: font,
       font_variants_count: font_variants_count,
       current_word: current_word,
       animator: animator
     }}
  end

  defp random_transition_for_index(i) do
    case i do
      0 ->
        &Transitions.push(&1, &2, direction: :right, steps: 60, separation: 3)

      9 ->
        &Transitions.push(&1, &2, direction: :left, steps: 60, separation: 3)

      _ ->
        if :rand.uniform() > 0.5 do
          &Transitions.push(&1, &2, direction: :top, steps: 60, separation: 3)
        else
          &Transitions.push(&1, &2, direction: :bottom, steps: 60, separation: 3)
        end
    end
  end

  def handle_info(
        :next_word,
        %{
          words: words,
          current_word: current_word,
          last_words: last_words,
          font: _font
        } = state
      ) do
    last_words = [current_word | last_words] |> Enum.take(param(:last_word_list_size, 250))
    next_word = Words.next(words, current_word, last_words)

    Logger.debug("Next Word: #{next_word}", next_word)

    String.split(state.current_word, "", trim: true)
    |> Enum.zip(String.split(next_word, "", trim: true))
    |> Enum.with_index()
    |> Enum.each(fn
      {{a, a}, _} ->
        nil

      {{_, b}, i} ->
        canvas = Canvas.new(8, 8) |> Canvas.put_string({0, 0}, b, state.font)

        :timer.send_after(
          :rand.uniform(param(:max_letter_delay, 1000)),
          {:animate_letter, i, canvas}
        )
    end)

    :timer.send_after(param(:word_duration, 5000), :next_word)
    {:noreply, %{state | last_words: last_words, current_word: next_word}}
  end

  def handle_info({:animate_letter, i, canvas}, state) do
    transition = random_transition_for_index(i)

    Animator.start_animation(
      state.animator,
      canvas,
      {8 * i, 0},
      transition,
      1500
    )

    {:noreply, state}
  end
end
