defmodule Octopus.Apps.Supermario.Game do
  @moduledoc """
  handles the game logic
  TODO most of current code will be moved to level.ex
  """
  alias __MODULE__
  alias Octopus.Apps.Supermario.PngFile

  @type t :: %__MODULE__{
          pixels: [],
          current_position: integer()
        }
  defstruct [
    :pixels,
    :current_position
  ]

  def new() do
    # TODO hard coded level
    pixels = PngFile.load_image_for_level(1)

    %Game{
      pixels: pixels,
      current_position: -1
    }
  end

  def tick(%Game{current_position: current_position} = game) do
    if current_position < max_position(game) do
      {:ok, %Game{game | current_position: current_position + 1}}
    else
      {:level_end, game}
    end
  end

  def current_pixels(%Game{pixels: pixels, current_position: current_position}) do
    Enum.map(pixels, fn row ->
      Enum.slice(row, current_position, 8)
    end)
  end

  defp max_position(%Game{pixels: pixels}), do: (Enum.at(pixels, 0) |> Enum.count()) - 8
end
