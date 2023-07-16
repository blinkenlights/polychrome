defmodule Octopus.Apps.Supermario.Game do
  @moduledoc """
  handles the game logic, still under heavy development
  some will move into level module
  mario movement is missing, some moving parts are missing
  """
  alias __MODULE__
  alias Octopus.Apps.Supermario.{Mario, PngFile}

  @type t :: %__MODULE__{
          pixels: [],
          state: :starting | :running | :paused | :gameover,
          current_position: integer(),
          windows_shown: integer(),
          last_ticker: Time.t(),
          current_level: integer(),
          mario: Mario.t()
        }
  defstruct [
    :pixels,
    :state,
    :current_position,
    :last_ticker,
    :windows_shown,
    :current_level,
    :mario
  ]

  # micro seconds between two moves
  @move_interval_ms 40_000
  @intro_animation_ms 3_000_000
  @pause_animation_ms 3_000_000
  @max_level 4

  def new(windows_shown) when windows_shown > 0 and windows_shown < 11 do
    current_level = 1

    %Game{
      current_level: current_level,
      pixels: load_level(current_level),
      state: :starting,
      current_position: -1,
      last_ticker: Time.utc_now(),
      windows_shown: windows_shown,
      mario: Mario.new()
    }
  end

  # intro animation
  def tick(%Game{last_ticker: last_ticker, state: :starting} = game) do
    now = Time.utc_now()

    if Time.diff(now, last_ticker, :microsecond) > @intro_animation_ms do
      {:ok, %Game{game | state: :running, last_ticker: now}}
    else
      {:ok, game}
    end
  end

  # between levels animation
  def tick(%Game{last_ticker: last_ticker, state: :paused, current_level: current_level} = game) do
    now = Time.utc_now()

    if Time.diff(now, last_ticker, :microsecond) > @pause_animation_ms do
      current_level = current_level + 1
      IO.inspect("starting level #{current_level}")
      # FIXME check max level => end game!!!, also check maxlevel is already done before????
      {:ok,
       %Game{
         game
         | state: :running,
           pixels: load_level(current_level),
           last_ticker: now,
           current_level: current_level,
           current_position: -1
       }}
    else
      {:ok, game}
    end
  end

  def tick(%Game{last_ticker: last_ticker, state: :running} = game) do
    now = Time.utc_now()

    if Time.diff(now, last_ticker, :microsecond) > @move_interval_ms do
      {:ok, %Game{game | last_ticker: now}}
    else
      {:ok, game}
    end
  end

  def move_left(%Game{current_position: 0, mario: mario} = game) do
    {:ok, %Game{game | mario: Mario.move_left(mario)}}
  end

  def move_left(
        %Game{
          current_position: current_position,
          mario: %Mario{} = mario
        } = game
      ) do
    if mario.x_position > Mario.start_position_x() do
      {:ok, %Game{game | mario: Mario.move_left(mario)}}
    else
      {:ok, %Game{game | current_position: current_position - 1}}
    end
  end

  def move_right(%Game{current_position: 0, mario: mario} = game) do
    if mario.x_position < Mario.start_position_x() do
      {:ok, %Game{game | mario: Mario.move_right(mario)}}
    else
      {:ok, %Game{game | current_position: 1}}
    end
  end

  def move_right(%Game{current_position: current_position, mario: mario} = game) do
    # TODO too many ifs, refactor
    if current_position < max_position(game) do
      {:ok, %Game{game | current_position: current_position + 1}}
    else
      if mario.x_position < 7 do
        {:ok, %Game{game | mario: Mario.move_right(mario)}}
      else
        if game.current_level <= @max_level do
          IO.inspect("level up, going to pause, level: #{game.current_level}")
          {:ok, %Game{game | state: :paused}}
        else
          IO.inspect("game over")
          {:game_over, %Game{game | state: :gameover}}
        end
      end
    end
  end

  # TODO intro animation
  def current_pixels(%Game{state: :starting}) do
    [
      [
        <<255, 255, 255, 255>>,
        <<0, 0, 0, 0>>,
        <<255, 255, 255, 255>>,
        <<0, 0, 0, 0>>,
        <<255, 255, 255, 255>>,
        <<0, 0, 0, 0>>,
        <<255, 255, 255, 255>>,
        <<0, 0, 0, 0>>
      ],
      [
        <<255, 255, 255, 255>>,
        <<0, 0, 0, 0>>,
        <<255, 255, 255, 255>>,
        <<0, 0, 0, 0>>,
        <<255, 255, 255, 255>>,
        <<0, 0, 0, 0>>,
        <<255, 255, 255, 255>>,
        <<0, 0, 0, 0>>
      ],
      [
        <<255, 255, 255, 255>>,
        <<0, 0, 0, 0>>,
        <<255, 255, 255, 255>>,
        <<0, 0, 0, 0>>,
        <<255, 255, 255, 255>>,
        <<0, 0, 0, 0>>,
        <<255, 255, 255, 255>>,
        <<0, 0, 0, 0>>
      ]
    ]
  end

  # TODO between levels animation
  def current_pixels(%Game{state: :pause}) do
    [
      [
        <<33, 44, 55, 255>>,
        <<0, 0, 0, 0>>,
        <<33, 44, 55, 255>>,
        <<0, 0, 0, 0>>,
        <<33, 44, 55, 255>>,
        <<0, 0, 0, 0>>,
        <<33, 44, 55, 255>>,
        <<0, 0, 0, 0>>
      ],
      [
        <<255, 255, 255, 255>>,
        <<0, 0, 0, 0>>,
        <<255, 255, 255, 255>>,
        <<0, 0, 0, 0>>,
        <<255, 255, 255, 255>>,
        <<0, 0, 0, 0>>,
        <<255, 255, 255, 255>>,
        <<0, 0, 0, 0>>
      ],
      [
        <<33, 44, 55, 255>>,
        <<0, 0, 0, 0>>,
        <<33, 44, 55, 255>>,
        <<0, 0, 0, 0>>,
        <<255, 255, 255, 255>>,
        <<33, 44, 55, 255>>,
        <<255, 255, 255, 255>>,
        <<33, 44, 55, 255>>
      ]
    ]
  end

  # FIXME missing game over animation

  # draw current pixels of level and mario
  def current_pixels(%Game{
        pixels: pixels,
        current_position: current_position,
        windows_shown: windows_shown,
        mario: mario
      }) do
    Enum.map(pixels, fn row ->
      Enum.slice(row, current_position, 8 * windows_shown)
    end)
    |> Mario.draw(mario)
  end

  defp load_level(level), do: PngFile.load_image_for_level(level)

  # TODO move to level module
  defp max_position(%Game{pixels: pixels}), do: (Enum.at(pixels, 0) |> Enum.count()) - 8
end
