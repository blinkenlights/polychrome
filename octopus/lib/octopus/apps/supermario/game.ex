defmodule Octopus.Apps.Supermario.Game do
  @moduledoc """
  handles the game logic, still under heavy development
  blocks are missing
  moving bad guy is missing
  moving blocks are missing
  """
  alias __MODULE__
  alias Octopus.Apps.Supermario.{Animation, Level, Mario}
  alias Octopus.Apps.Supermario.Animation.MarioDies

  @type t :: %__MODULE__{
          state: :starting | :running | :paused | :mario_dies | :gameover | :completed,
          current_position: integer(),
          windows_shown: integer(),
          last_ticker: Time.t(),
          level: Level.t(),
          mario: Mario.t(),
          current_animation: Animation.t() | nil
        }
  defstruct [
    :state,
    :current_position,
    :last_ticker,
    :windows_shown,
    :level,
    :mario,
    :current_animation
  ]

  # micro seconds between two moves
  @update_interval_ms 10_000
  @intro_animation_ms 3_000_000
  @dying_animation_ms 3_000_000
  @pause_animation_ms 3_000_000

  def new(windows_shown) when windows_shown > 0 and windows_shown < 11 do
    %Game{
      level: Level.new(),
      state: :starting,
      current_position: 0,
      last_ticker: Time.utc_now(),
      windows_shown: windows_shown,
      mario: Mario.new(),
      current_animation: nil
    }
  end

  def restart(%Game{level: level} = game) do
    %Game{
      game
      | level: Level.restart(level),
        state: :running,
        current_position: 0,
        last_ticker: Time.utc_now(),
        mario: Mario.new(),
        current_animation: nil
    }
  end

  # intro animation
  def tick(%Game{last_ticker: last_ticker, state: :starting, current_animation: nil} = game) do
    {:ok, %Game{game | current_animation: Octopus.Apps.Supermario.Animation.Intro.new()}}
  end

  def tick(%Game{last_ticker: last_ticker, state: :starting} = game) do
    now = Time.utc_now()

    if Time.diff(now, last_ticker, :microsecond) > @intro_animation_ms do
      {:ok, %Game{game | state: :running, last_ticker: now, current_animation: nil}}
    else
      {:ok, game}
    end
  end

  def tick(%Game{last_ticker: last_ticker, state: :mario_dies} = game) do
    now = Time.utc_now()

    if Time.diff(now, last_ticker, :microsecond) > @dying_animation_ms do
      # restart game
      {:ok, Game.restart(game)}
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
    {:ok, %Game{game | mario: Mario.move_left(mario, game.level)}}
  end

  def move_left(
        %Game{
          current_position: current_position,
          mario: %Mario{} = mario
        } = game
      ) do
    game =
      if mario.x_position > Mario.start_position_x() do
        %Game{game | mario: Mario.move_left(mario, game.level)}
      else
        if Mario.can_move_left?(mario, game) do
          %Game{game | current_position: current_position - 1}
        else
          game
        end
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
      {:ok, %Game{game | mario: Mario.move_right(mario, game.level)}}
    else
      {:ok, %Game{game | current_position: 1}}
    end
  end

  def move_right(%Game{current_position: current_position, mario: mario, level: level} = game) do
    # TODO too many nested ifs, refactor, use case statement
    if current_position < Level.max_position(level) do
      if Mario.can_move_right?(mario, game) do
        {:ok, %Game{game | current_position: current_position + 1}}
      else
        {:ok, game}
      end
    else
      if mario.x_position < 7 do
        {:ok, %Game{game | mario: Mario.move_right(mario, level)}}
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
    mario = Mario.jump(mario, game.level)
    %Game{game | mario: mario}
  end

  # called by tick in intervals
  def update(%Game{mario: mario} = game) do
    mario = Mario.update(mario, game)
    # TODO: check also for bonus points
    if Game.mario_dies?(game) do
      # init dying animation
      # get current pixels and mario position
      animation =
        game
        |> current_game_pixels()
        |> MarioDies.new({
          mario.x_position,
          mario.y_position
        })

      # FIX>ME reduce mario lives!!!!!!
      {:mario_dies,
       %Game{
         game
         | mario: mario,
           state: :mario_dies,
           last_ticker: Time.utc_now(),
           current_animation: animation
       }}
    else
      {:ok, %Game{game | mario: mario}}
    end
  end

  # varios ways to die
  # currently the only way is to fall down
  # will have to check the level for enemies etc.
  def mario_dies?(%Game{mario: mario}) do
    mario.y_position >= 7
  end

  # Game draw just returns pixels TODO find a better name
  # TODO intro animation
  def draw(%Game{state: :starting, current_animation: nil}) do
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
  def draw(%Game{state: :pause, current_animation: nil}) do
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

  # TODO game over animation
  def draw(%Game{state: :gameover, current_animation: nil}) do
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

  # draw current pixels of level and mario
  def draw(
        %Game{
          mario: mario,
          current_animation: nil
        } = game
      ) do
    game
    |> current_game_pixels
    |> Mario.draw(mario)
  end

  def draw(%Game{current_animation: current_animation}) do
    Animation.draw(current_animation)
  end

  defp current_game_pixels(
         %Game{
           level: level,
           current_position: current_position,
           windows_shown: windows_shown
         } = game
       ) do
    Enum.map(level.pixels, fn row ->
      Enum.slice(row, current_position, 8 * windows_shown)
    end)
  end
end
