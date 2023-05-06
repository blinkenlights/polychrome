defmodule Octopus.SpriteTester do
  alias Octopus.Broadcaster
  use GenServer

  require Logger

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(_) do
    :timer.send_interval(1000, :tick)

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
    Broadcaster.send(%Octopus.Protobuf.Frame{
      data: IO.iodata_to_binary(get_sprite(state.atlas, state.idx))
    })

    pixels =
      if rem(state.idx, 2) != 0 do
        List.duplicate(0, 64)
      else
        get_sprite(state.atlas, trunc(state.idx / 2))
        |> Enum.map(&:binary.bin_to_list/1)
        |> Enum.map(&Enum.take(&1, 3))
        |> Enum.map(&Enum.find_index(state.palette, fn value -> value == &1 end))
      end

    config = %Octopus.Protobuf.Config{
      color_palette:
        state.palette |> Enum.map(&(&1 ++ [0])) |> IO.inspect() |> IO.iodata_to_binary(),
      easing_interval_ms: 1000,
      pixel_easing: :LINEAR,
      brightness_easing: :LINEAR,
      show_test_frame: false
    }

    IO.inspect(pixels)

    frame = %Octopus.Protobuf.Frame{data: pixels |> IO.iodata_to_binary()}

    Broadcaster.send(config)
    Broadcaster.send(frame)

    {:noreply, %{state | idx: state.idx + 1}}
  end

  # get the sprite at the given index
  defp get_sprite(atlas, idx) do
    pixels =
      for y <- 0..7 |> Enum.reverse(), x <- 0..7 do
        ExPng.Image.at(atlas, {x + rem(idx * 8, 128), y + trunc(idx / 16) * 8})
      end

    pixels
  end
end
