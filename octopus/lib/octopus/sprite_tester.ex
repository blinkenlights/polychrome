defmodule Octopus.SpriteTester do
  alias Octopus.Broadcaster
  use GenServer

  require Logger

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(_) do
    :timer.send_interval(500, :tick)

    {:ok, sprite} =
      ExPng.Image.from_file(
        Path.join(:code.priv_dir(:octopus), "sprites/256-characters-original.png")
      )

    palette =
      ExPng.Image.unique_pixels(sprite)
      |> Enum.map(&:binary.bin_to_list/1)
      |> Enum.map(&Enum.take(&1, 3))

    {:ok, %{idx: 0, atlas: sprite, palette: palette}}
  end

  def handle_info(:tick, state) do
    pixels =
      0..9
      |> Enum.flat_map(&get_sprite(state.atlas, trunc(state.idx + &1)))
      |> Enum.map(&Enum.take(&1, 3))
      |> Enum.map(&Enum.find_index(state.palette, fn value -> value == &1 end))

    config = %Octopus.Protobuf.Config{
      # color_palette: state.palette |> Enum.map(&(&1 ++ [0])) |> IO.iodata_to_binary(),
      # easing_interval_ms: 500,
      # pixel_easing: :LINEAR,
      # brightness_easing: :LINEAR,
      # show_test_frame: false
    }

    frame = %Octopus.Protobuf.Frame{data: pixels |> IO.iodata_to_binary()}

    Broadcaster.send(config)
    Broadcaster.send(frame)

    {:noreply, %{state | idx: state.idx + 1}}
  end

  defp get_sprite(atlas, idx, flip_y \\ false) do
    y_range = if flip_y, do: 7..0, else: 0..7

    for y <- y_range, x <- 0..7 do
      ExPng.Image.at(atlas, {x + rem(idx * 8, 128), y + rem(trunc(idx / 16), 16 * 8) * 8})
    end
    |> Enum.map(&:binary.bin_to_list/1)
  end
end
