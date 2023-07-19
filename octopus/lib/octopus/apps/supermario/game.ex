defmodule Octopus.Apps.Supermario.Game do
  @moduledoc """
  handles the game logic, still under heavy development
  blocks are missing
  moving bad guy is missing
  moving blocks are missing
  """
  alias __MODULE__
  alias Octopus.Apps.Supermario.{Level, Mario}

  @type t :: %__MODULE__{
          state: :starting | :running | :paused | :gameover,
          current_position: integer(),
          windows_shown: integer(),
          last_ticker: Time.t(),
          level: Level.t(),
          mario: Mario.t()
        }
  defstruct [
    :state,
    :current_position,
    :last_ticker,
    :windows_shown,
    :level,
    :mario
  ]

  # micro seconds between two moves
  @update_interval_ms 10_000
  @intro_animation_ms 3_000_000
  @pause_animation_ms 3_000_000

  def new(windows_shown) when windows_shown > 0 and windows_shown < 11 do
    %Game{
      level: Level.new(),
      state: :starting,
      current_position: 0,
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
  def tick(%Game{last_ticker: last_ticker, state: :paused, level: level} = game) do
    now = Time.utc_now()

    if Time.diff(now, last_ticker, :microsecond) > @pause_animation_ms do
      # FIXME check max level => end game!!!, also check maxlevel is already done before????
      #       second thought, this should have been done before the pause animation => CEHECK
      {:ok,
       %Game{
         game
         | state: :running,
           level: Level.next_level(level),
           last_ticker: now,
           current_position: 0
       }}
    else
      {:ok, game}
    end
  end

  def tick(%Game{last_ticker: last_ticker, state: :running} = game) do
    now = Time.utc_now()

    if Time.diff(now, last_ticker, :microsecond) > @update_interval_ms do
      Game.update(game)
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
    game =
      if mario.x_position > Mario.start_position_x() do
        %Game{game | mario: Mario.move_left(mario)}
      else
        %Game{game | current_position: current_position - 1}
      end

    # FIXME: check if mario is dead
    if true do
      {:ok, game}
    else
      {:game_over, game}
    end
  end

  def move_right(%Game{current_position: 0, mario: mario} = game) do
    if mario.x_position < Mario.start_position_x() do
      {:ok, %Game{game | mario: Mario.move_right(mario)}}
    else
      {:ok, %Game{game | current_position: 1}}
    end
  end

  def move_right(%Game{current_position: current_position, mario: mario, level: level} = game) do
    # TODO too many nested ifs, refactor, use case statement
    if current_position < Level.max_position(level) do
      {:ok, %Game{game | current_position: current_position + 1}}
    else
      if mario.x_position < 7 do
        {:ok, %Game{game | mario: Mario.move_right(mario)}}
      else
        if Level.last_level?(game.level) do
          IO.inspect("game over")
          {:game_over, %Game{game | state: :gameover}}
        else
          {:ok, %Game{game | state: :paused}}
        end
      end
    end
  end

  def jump(%Game{mario: mario} = game) do
    mario = Mario.jump(mario)
    %Game{game | mario: mario}
  end

  def update(%Game{mario: mario} = game) do
    {:ok, %Game{game | mario: Mario.update(mario)}}
  end

  # TODO intro animation
  def draw(%Game{state: :starting}) do
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
  def draw(%Game{state: :pause}) do
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
  def draw(%Game{
        level: level,
        current_position: current_position,
        windows_shown: windows_shown,
        mario: mario
      }) do
    Enum.map(level.pixels, fn row ->
      Enum.slice(row, current_position, 8 * windows_shown)
    end)
    |> Mario.draw(mario)
  end
end
