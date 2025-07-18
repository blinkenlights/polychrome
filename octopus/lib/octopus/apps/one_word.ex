defmodule Octopus.Apps.OneWord do
  use Octopus.App, category: :animation, output_type: :grayscale
  use Octopus.Params, prefix: :one_word

  alias Octopus.Font
  alias Octopus.Canvas

  require Logger

  defmodule Words do
    defstruct [:words]

    def load(path) do
      words =
        path
        |> File.read!()
        |> String.split("\n", trim: true)
        |> Enum.filter(fn word -> String.length(word) == 10 end)
        |> Enum.map(&String.upcase/1)

      %__MODULE__{words: words}
    end

    def random(%__MODULE__{words: words}) do
      Enum.random(words)
    end
  end

  def name, do: "One Word"

  def icon(), do: Canvas.from_string("1", Font.load("BlinkenLightsRegular"), 3)

  def app_init(_) do
    # Configure display for grayscale output using modern unified API
    Octopus.App.configure_display(
      layout: :adjacent_panels,
      supports_rgb: false,
      supports_grayscale: true,
      easing_interval: 150
    )

    # Get display info for dynamic sizing
    display_info = Octopus.App.get_display_info()

    path = Path.join([:code.priv_dir(:octopus), "words", "nog24-256-10--letter-words.txt"])
    words = Words.load(path)

    # Select a random word
    selected_word = Words.random(words)

    Logger.debug("Selected word: #{selected_word}")

    # Display the word immediately
    font = Font.load("BlinkenLightsRegular")

    # Create grayscale canvas with the selected word directly
    canvas = Canvas.new(display_info.width, display_info.height, :grayscale)
    canvas = Canvas.put_string(canvas, {0, 0}, selected_word, font)

    # Send a message to display the word (like StaticImage does)
    :timer.send_after(10, {:display_word, canvas})

    # Schedule the app to go black and stop after the configured duration
    duration_ms = param(:duration_seconds, 5) * 1000
    :timer.send_after(duration_ms, :go_black_and_stop)

    {:ok,
     %{
       word: selected_word,
       display_info: display_info,
       font: font,
       timer: duration_ms
     }}
  end

  def handle_info({:display_word, canvas}, state) do
    Logger.debug("Displaying word: #{state.word}")

    # Log the canvas content for debugging
    Logger.debug("Canvas bitmap: #{inspect(canvas)}")

    # Update display with the word
    Octopus.App.update_display(canvas, :grayscale, easing_interval: 250)

    if state.timer > 0 do
      :timer.send_after(20, {:display_word, canvas})
    else
      send(self(), :go_black_and_stop)
    end

    {:noreply, %{state | timer: state.timer - 20}}
  end

  def handle_info(:go_black_and_stop, state) do
    Logger.debug("Going black and stopping OneWord app")

    # Create a black grayscale canvas directly
    black_canvas = Canvas.new(state.display_info.width, state.display_info.height, :grayscale)

    # Update display to black
    Octopus.App.update_display(black_canvas, :grayscale, easing_interval: 150)

    # Stop the app using the proper supervisor method
    app_id = Octopus.AppSupervisor.lookup_app_id(self())
    Octopus.AppSupervisor.stop_app(app_id)

    {:noreply, state}
  end

  def handle_info(msg, state) do
    Logger.warning("Unexpected message in One Word: #{inspect(msg)}")
    {:noreply, state}
  end
end
