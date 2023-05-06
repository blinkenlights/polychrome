defmodule Octopus.FontTester do
  alias Octopus.Broadcaster
  use GenServer

  require Logger

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(_) do
    {:ok, %{fonts: %{}}}
  end

  def animate do
    "ALL YOUR BASE ARE BELONG TO US"
    |> String.to_charlist()
    |> Stream.cycle()
    |> Stream.map(fn c ->
      Process.sleep(1000)
      Octopus.FontTester.display_char(c, "zwing-Zero Wing (Toaplan).png", 0)
    end)
    |> Stream.run()
  end

  def display_char(char, font, variant \\ 0) do
    GenServer.cast(__MODULE__, {:display_char, char, font, variant})
  end

  def animate_char(char, font, variant \\ 0) do
    GenServer.cast(__MODULE__, {:animate, char, font, variant})
  end

  def handle_cast({:display_char, char, font, variant}, state) do
    font = state.fonts |> Map.get_lazy(font, fn -> Font.load_font(font) end)

    {pixels, palette} = Font.get_char(font, char, variant)

    config = %Octopus.Protobuf.Config{
      color_palette: palette |> List.flatten() |> IO.iodata_to_binary(),
      easing_interval_ms: 300,
      pixel_easing: :LINEAR,
      brightness_easing: :LINEAR,
      show_test_frame: false
    }

    frame = %Octopus.Protobuf.Frame{data: pixels |> IO.iodata_to_binary()}

    Broadcaster.send(config)
    Broadcaster.send(frame)

    {:noreply, state}
  end
end
