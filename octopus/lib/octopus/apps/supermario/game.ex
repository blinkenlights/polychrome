defmodule Octopus.Apps.Supermario.Game do
  @moduledoc """
  handles the game logic
  TODO most of current code will be moved to level.ex
  """
  alias __MODULE__
  alias Octopus.Apps.Supermario.PngFile

  @type t :: %__MODULE__{
          pixels: [],
          current_position: integer(),
          windows_shown: integer(),
          last_ticker: Time.t()
        }
  defstruct [
    :pixels,
    :current_position,
    :last_ticker,
    :windows_shown
  ]

  # micro seconds between two moves
  @move_interval_ms 80_000

  def new(windows_shown) when windows_shown > 0 and windows_shown < 11 do
    # TODO hard coded level
    pixels = PngFile.load_image_for_level(1)

    %Game{
      pixels: pixels,
      current_position: -1,
      last_ticker: Time.utc_now(),
      windows_shown: windows_shown
    }
  end

  def tick(%Game{current_position: current_position, last_ticker: last_ticker} = game) do
    # only move every ?? ms
    now = Time.utc_now()

    if Time.diff(now, last_ticker, :microsecond) > @move_interval_ms do
      if current_position < max_position(game) do
        {:ok, %Game{game | current_position: current_position + 1, last_ticker: now}}
      else
        {:level_end, game}
      end
    else
      {:ok, game}
    end
  end

  def current_pixels(%Game{
        pixels: pixels,
        current_position: current_position,
        windows_shown: windows_shown
      }) do
    Enum.map(pixels, fn row ->
      Enum.slice(row, current_position, 8 * windows_shown)
    end)
  end

  defp max_position(%Game{pixels: pixels}), do: (Enum.at(pixels, 0) |> Enum.count()) - 8
end
