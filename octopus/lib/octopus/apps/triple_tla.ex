defmodule Octopus.Apps.TripleTla do
  use Octopus.App, category: :animation, output_type: :grayscale
  use Octopus.Params, prefix: :triple_tla

  alias Octopus.Font
  alias Octopus.Transitions
  alias Octopus.Canvas
  alias Octopus.Animator
  alias Octopus.Events.Event.Input, as: InputEvent

  require Logger

  defmodule TlaWords do
    defstruct [:words, :lookup]

    def load(path) do
      words =
        path
        |> File.read!()
        |> String.split("\n", trim: true)
        |> Enum.filter(fn word -> String.length(word) == 3 end)
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

          new_candidates =
            if length(new_candidates) > 30 do
              Enum.drop(new_candidates, 20)
            else
              new_candidates
            end
            |> Enum.take(10)

          {index_1, new_candidates}
        end)
        |> Enum.into(%{})

      %__MODULE__{words: words |> Enum.to_list() |> Enum.map(&elem(&1, 0)), lookup: lookup}
    end

    def next(%__MODULE__{words: words, lookup: lookup}, current_word, exclude \\ []) do
      current_word_index = Enum.find_index(words, &(&1 == current_word))

      candidate =
        case lookup[current_word_index] do
          nil ->
            # Current word not found in lookup (e.g., spaces), return empty list to trigger random selection
            []

          candidates ->
            candidates
            |> Stream.map(&Enum.at(words, &1))
            |> Stream.reject(fn word -> word in exclude end)
            |> Enum.take(1)
        end

      case candidate do
        [] -> Enum.random(words)
        [word | _] -> word
      end
    end

    def next_with_target_position(
          %__MODULE__{words: words},
          current_word,
          target_position,
          exclude \\ []
        ) do
      current_letters = String.graphemes(current_word)

      # Find words that ideally only change the target position letter
      candidates =
        words
        |> Stream.reject(fn word -> word in exclude or word == current_word end)
        |> Stream.map(fn word ->
          word_letters = String.graphemes(word)
          changes = count_letter_changes(current_letters, word_letters)

          target_changed =
            Enum.at(current_letters, target_position) != Enum.at(word_letters, target_position)

          {word, changes, target_changed}
        end)
        |> Enum.to_list()

      # Prioritize words where:
      # 1. Target position changes (most important)
      # 2. Fewest total changes (prefer single letter changes)
      best_candidate =
        candidates
        |> Enum.filter(fn {_word, _changes, target_changed} -> target_changed end)
        |> Enum.sort_by(fn {_word, changes, _target_changed} -> changes end)
        |> List.first()

      case best_candidate do
        {word, _changes, _target_changed} ->
          word

        nil ->
          # Fallback: if no word changes target position, find word with minimal changes
          fallback =
            candidates
            |> Enum.sort_by(fn {_word, changes, _target_changed} -> changes end)
            |> List.first()

          case fallback do
            {word, _changes, _target_changed} -> word
            # Ultimate fallback
            nil -> Enum.random(words)
          end
      end
    end

    defp count_letter_changes(letters1, letters2) do
      letters1
      |> Enum.zip(letters2)
      |> Enum.count(fn {a, b} -> a != b end)
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

  def name, do: "Triple TLA"

  def icon(), do: Canvas.from_string("3", Font.load("BlinkenLightsRegular"), 3)

  def compatible?() do
    # Only compatible with 12-panel circular installations
    installation_info = get_installation_info()

    installation_info.panel_count == 12 and Octopus.Installation.arrangement() == :circular
  end

  def app_init(_) do
    # Configure display for grayscale output using modern unified API
    Octopus.App.configure_display(
      layout: :adjacent_panels,
      supports_rgb: false,
      supports_grayscale: true,
      easing_interval: 150
    )

    # Subscribe to button events for manual mode
    Octopus.App.subscribe_to_button_events()

    # Get display info for dynamic sizing
    display_info = Octopus.App.get_display_info()

    path = Path.join([:code.priv_dir(:octopus), "words", "tla-words.txt"])
    words = TlaWords.load(path)

    font = Font.load("BlinkenLightsRegular")

    # Initialize with blank TLAs (will be populated immediately)
    current_tlas = ["   ", "   ", "   "]

    # Initialize with a blank display
    blank_canvas = Canvas.new(display_info.width, display_info.height)
    grayscale_canvas = Canvas.to_grayscale(blank_canvas)
    Octopus.App.update_display(grayscale_canvas, :grayscale, easing_interval: 150)

    # Trigger immediate first word display for all sections
    for section <- 0..2 do
      :timer.send_after(100 + section * 50, {:next_word, section})
    end

    # Set up automatic timers only in automatic mode
    mode = param(:mode, :manual)

    if mode == :automatic do
      speed = param(:speed, 1.0)
      base_duration = param(:word_duration, 5000)
      duration = round(base_duration / speed)

      # Start regular automatic timers after initial display
      for section <- 0..2 do
        delay = duration + :rand.uniform(round(duration * 0.3))
        :timer.send_after(delay, {:next_word, section})
      end
    end

    {:ok,
     %{
       words: words,
       # Separate history for each section
       last_words: [[], [], []],
       font: font,
       current_tlas: current_tlas,
       display_info: display_info,
       # Track individual letter canvases for each section
       letter_canvases: %{},
       # Operational mode: :automatic or :manual
       mode: mode,
       speed: param(:speed, 1.0)
     }}
  end

  # Section panel mappings: 0->panels 1-3, 1->panels 5-7, 2->panels 9-11
  # panels 1-3 (0-indexed)
  defp section_to_panels(0), do: [0, 1, 2]
  # panels 5-7 (0-indexed)
  defp section_to_panels(1), do: [4, 5, 6]
  # panels 9-11 (0-indexed)
  defp section_to_panels(2), do: [8, 9, 10]

  defp button_to_section(button) when button in [1, 2, 3], do: 0
  defp button_to_section(button) when button in [5, 6, 7], do: 1
  defp button_to_section(button) when button in [9, 10, 11], do: 2
  # Buttons 4, 8, 12 are ignored (gap panels)
  defp button_to_section(_), do: nil

  # Map button to letter position within its section (0, 1, or 2)
  defp button_to_letter_position(button, 0) when button in [1, 2, 3], do: button - 1
  defp button_to_letter_position(button, 1) when button in [5, 6, 7], do: button - 5
  defp button_to_letter_position(button, 2) when button in [9, 10, 11], do: button - 9

  defp random_transition_for_index(i) do
    case rem(i, 3) do
      0 ->
        &Transitions.push(&1, &2, direction: :right, separation: 3)

      2 ->
        &Transitions.push(&1, &2, direction: :left, separation: 3)

      _ ->
        if :rand.uniform() > 0.5 do
          &Transitions.push(&1, &2, direction: :top, separation: 3)
        else
          &Transitions.push(&1, &2, direction: :bottom, separation: 3)
        end
    end
  end

  def handle_info({:next_word, section}, %{mode: :automatic} = state) do
    handle_next_word(section, state)
  end

  def handle_info({:next_word, section}, %{mode: :manual, current_tlas: current_tlas} = state) do
    # In manual mode, only allow word change if current word is blank (initial setup)
    current_word = Enum.at(current_tlas, section)

    if current_word == "   " do
      # Allow initial word display in manual mode
      handle_next_word(section, state)
    else
      # Ignore automatic timers for non-blank words in manual mode
      {:noreply, state}
    end
  end

  def handle_info({:animator_update, animation_id, canvas, frame_status}, state) do
    # Handle canvas updates from the Animator module with animation identification
    updated_state =
      case animation_id do
        {:letter, panel_index} ->
          # Update the specific letter canvas
          update_letter_canvas(state, panel_index, canvas, frame_status)

        _ ->
          # For other animations, convert to grayscale and update display
          grayscale_canvas = Canvas.to_grayscale(canvas)
          Octopus.App.update_display(grayscale_canvas, :grayscale, easing_interval: 150)
          state
      end

    {:noreply, updated_state}
  end

  def handle_info(
        {:animate_letter, panel_idx, target_canvas},
        %{display_info: display_info} = state
      ) do
    transition = random_transition_for_index(panel_idx)

    # Check if we have any existing letter canvas for this panel position
    existing_letter_canvas = Map.get(state.letter_canvases, panel_idx)

    current_canvas =
      if existing_letter_canvas do
        # Use the existing animated letter canvas
        existing_letter_canvas
      else
        # For positions without existing letters, start from blank (which represents spaces)
        Canvas.new(display_info.panel_width, display_info.panel_height)
      end

    # Create a transition function that uses the current state as the starting point
    transition_with_current = fn _blank_canvas, to_canvas ->
      # Ignore the blank canvas from Animator and use our current state canvas
      transition.(current_canvas, to_canvas)
    end

    # Use new single-call API for letter animation
    animation_duration = round(1500 / state.speed)

    Animator.animate(
      animation_id: {:letter, panel_idx},
      app_pid: self(),
      canvas: target_canvas,
      position: {0, 0},
      transition_fun: transition_with_current,
      duration: animation_duration,
      canvas_size: {display_info.panel_width, display_info.panel_height},
      frame_rate: 30
    )

    {:noreply, state}
  end

  def handle_info(msg, state) do
    Logger.warning("Unexpected message in Triple TLA: #{inspect(msg)}")
    {:noreply, state}
  end

  defp handle_next_word(section, state) do
    %{
      words: words,
      current_tlas: current_tlas,
      last_words: last_words,
      display_info: display_info,
      speed: speed
    } = state

    current_word = Enum.at(current_tlas, section)
    section_history = Enum.at(last_words, section)

    updated_history =
      [current_word | section_history] |> Enum.take(param(:last_word_list_size, 50))

    next_word = TlaWords.next(words, current_word, updated_history)

    Logger.debug("Section #{section} - Next Word: #{next_word}")

    # Update state
    updated_tlas = List.replace_at(current_tlas, section, next_word)
    updated_histories = List.replace_at(last_words, section, updated_history)

    # Animate letters that changed
    current_letters = String.split(current_word, "", trim: true)
    next_letters = String.split(next_word, "", trim: true)
    section_panels = section_to_panels(section)

    current_letters
    |> Enum.zip(next_letters)
    |> Enum.with_index()
    |> Enum.each(fn
      {{a, a}, _} ->
        nil

      {{_, b}, letter_idx} ->
        panel_idx = Enum.at(section_panels, letter_idx)

        canvas =
          Canvas.new(display_info.panel_width, display_info.panel_height)
          |> Canvas.put_string({0, 0}, b, state.font)

        max_delay = round(param(:max_letter_delay, 1000) / speed)

        :timer.send_after(
          :rand.uniform(max_delay),
          {:animate_letter, panel_idx, canvas}
        )
    end)

    # Schedule next word change for this section (only in automatic mode)
    if state.mode == :automatic do
      duration = round(param(:word_duration, 5000) / speed)
      :timer.send_after(duration, {:next_word, section})
    end

    {:noreply, %{state | last_words: updated_histories, current_tlas: updated_tlas}}
  end

  defp handle_targeted_word_change(section, target_letter_position, state) do
    %{
      words: words,
      current_tlas: current_tlas,
      last_words: last_words,
      display_info: display_info,
      speed: speed
    } = state

    current_word = Enum.at(current_tlas, section)
    section_history = Enum.at(last_words, section)

    updated_history =
      [current_word | section_history] |> Enum.take(param(:last_word_list_size, 50))

    # Use targeted word selection
    next_word =
      TlaWords.next_with_target_position(
        words,
        current_word,
        target_letter_position,
        updated_history
      )

    Logger.info(
      "Section #{section} - Targeted change at position #{target_letter_position}: #{current_word} → #{next_word}"
    )

    # Update state
    updated_tlas = List.replace_at(current_tlas, section, next_word)
    updated_histories = List.replace_at(last_words, section, updated_history)

    # Animate letters that changed
    current_letters = String.split(current_word, "", trim: true)
    next_letters = String.split(next_word, "", trim: true)
    section_panels = section_to_panels(section)

    current_letters
    |> Enum.zip(next_letters)
    |> Enum.with_index()
    |> Enum.each(fn
      {{a, a}, _} ->
        nil

      {{_, b}, letter_idx} ->
        panel_idx = Enum.at(section_panels, letter_idx)

        canvas =
          Canvas.new(display_info.panel_width, display_info.panel_height)
          |> Canvas.put_string({0, 0}, b, state.font)

        max_delay = round(param(:max_letter_delay, 1000) / speed)

        :timer.send_after(
          :rand.uniform(max_delay),
          {:animate_letter, panel_idx, canvas}
        )
    end)

    # No automatic scheduling in manual mode
    {:noreply, %{state | last_words: updated_histories, current_tlas: updated_tlas}}
  end

  # Handle button presses in manual mode
  def handle_event(
        %InputEvent{type: :button, action: :press, button: button_id},
        %{mode: :manual} = state
      ) do
    Logger.info("Triple TLA: Button #{button_id} pressed in manual mode")

    case button_to_section(button_id) do
      nil ->
        Logger.info("Triple TLA: Button #{button_id} does not map to any section")
        {:noreply, state}

      section ->
        # Determine which letter position within the section this button targets
        target_letter_position = button_to_letter_position(button_id, section)

        Logger.info(
          "Triple TLA: Button #{button_id} mapped to section #{section}, letter position #{target_letter_position} - triggering targeted word change"
        )

        handle_targeted_word_change(section, target_letter_position, state)
    end
  end

  def handle_event(
        %InputEvent{type: :button, action: :press, button: _button_id},
        %{mode: :automatic} = state
      ) do
    # In automatic mode, ignore button presses
    {:noreply, state}
  end

  def handle_event(_event, state) do
    # Ignore other input types and events
    {:noreply, state}
  end

  defp update_letter_canvas(state, panel_index, canvas, _frame_status) do
    # Get current letter canvases
    letter_canvases = Map.get(state, :letter_canvases, %{})
    updated_letter_canvases = Map.put(letter_canvases, panel_index, canvas)

    # Start with a blank canvas and only show animated letters
    background_canvas = Canvas.new(state.display_info.width, state.display_info.height)

    # Overlay animated letters on the blank background
    new_display_canvas =
      Enum.reduce(updated_letter_canvases, background_canvas, fn {panel_idx, letter_canvas},
                                                                 acc ->
        x_offset = panel_idx * state.display_info.panel_width
        Canvas.overlay(acc, letter_canvas, offset: {x_offset, 0})
      end)

    # Convert to grayscale and update display
    grayscale_canvas = Canvas.to_grayscale(new_display_canvas)

    # Update display
    Octopus.App.update_display(grayscale_canvas, :grayscale, easing_interval: 150)

    # Update state with new letter canvases
    Map.put(state, :letter_canvases, updated_letter_canvases)
  end
end
