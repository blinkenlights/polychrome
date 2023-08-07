defmodule Octopus.Apps.Supermario.Game do
  @moduledoc """
  handles the game logic
  """
  alias __MODULE__
  alias Octopus.Apps.Supermario.{Animation, Level, Mario}
  alias Octopus.Apps.Supermario.Animation.{Intro, MarioDies}

  @type t :: %__MODULE__{
          state: :starting | :running | :paused | :mario_dies | :gameover | :completed,
          current_position: integer(),
          windows_shown: integer(),
          last_ticker: Time.t(),
          level: Level.t(),
          mario: Mario.t(),
          current_animation: Animation.t() | nil,
          lives: integer()
        }
  defstruct [
    :state,
    :current_position,
    :last_ticker,
    :windows_shown,
    :level,
    :mario,
    :current_animation,
    :lives,
    :score
  ]

  # micro seconds between two moves
  @update_interval_ms 10_000
  @intro_animation_ms 3_000_000
  @dying_animation_ms 3_000_000
  @pause_animation_ms 3_000_000

  def new(windows_shown) when windows_shown > 0 and windows_shown < 11 do
    level = Level.new()
    %Game{
      level: level,
      state: :starting,
      current_position: 0,
      last_ticker: Time.utc_now(),
      windows_shown: windows_shown,
      mario: Mario.new(level.mario_start_y_position),
      current_animation: nil,
      lives: 3,
      score: 0
    }
  end

  def restart(%Game{level: level} = game) do
    %Game{
      game
      | level: Level.restart(level),
        state: :running,
        current_position: 0,
        last_ticker: Time.utc_now(),
        mario: Mario.new(level.mario_start_y_position),
        current_animation: nil
    }
  end

  # intro animation
  def tick(%Game{state: :starting, current_animation: nil} = game) do
    {:ok, %Game{game | current_animation: Intro.new()}}
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
      #
      next_level = Level.next_level(level)
      {:ok,
       %Game{
         game
         | state: :running,
           level: next_level,
           last_ticker: now,
           current_position: 0,
           mario: Mario.new(next_level.mario_start_y_position)
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

  def tick(%Game{state: :gameover} = game) do
    {:ok, game}
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
          # FIXME add score
          {:ok, %Game{game | state: :paused}}
        end
      end
    end
  end

  def jump(%Game{mario: mario} = game) do
    mario = Mario.jump(mario, game)
    %Game{game | mario: mario}
  end

  defp update_mario(game), do: check_mario_fall(game)

  defp check_mario_fall(%Game{mario: mario} = game) do
    case Mario.fall_if(mario, game) do
      {true, mario} ->
        mario_has_fallen(%Game{game | mario: mario})

      {false, mario} ->
        %Game{game | mario: mario}
    end
  end

  defp mario_has_fallen(
         %Game{
           mario: %Mario{y_position: y_position, x_position: x_position},
           current_position: current_position,
           level: level
         } = game
       ) do
    absolute_x_position = current_position + x_position

    # check wether we fall on bad guy
    game = if Level.has_bad_guy_on_postion?(level, absolute_x_position, y_position) do
      # FIXME add score points!!!
      %Game{game | level: Level.kill_bad_guy(level, absolute_x_position, y_position)}
    else
      game
    end
    # when we ware falling on the ground reset the jump counter
    if !Mario.can_fall?(game.mario, game) do
      %Game{game | mario: Mario.reset_jumps(game.mario)}
    else
      game
    end
  end

  # called by tick in intervals
  def update(%Game{} = game) do
    game =
      game
      |> Level.update()
      |> update_mario()

    if Game.mario_dies?(game) do

     mario_has_died(game)
    else
      {:ok, game}
    end
  end

  # last live: game over!!
  def mario_has_died(%Game{lives: 1} = game) do
    {:game_over, %Game{game | state: :gameover}}
  end

  # init dying animation: get current pixels and mario position
  def mario_has_died(%Game{} = game) do
    animation =
      game
      |> current_game_pixels()
      |> MarioDies.new({
        game.mario.x_position,
        game.mario.y_position
      })

    {:mario_dies,
     %Game{
       game
       | mario: game.mario,
         state: :mario_dies,
         last_ticker: Time.utc_now(),
         current_animation: animation,
         lives: game.lives - 1
     }}
  end

  # varios ways to die
  # when mario falls down
  def mario_dies?(%Game{mario: %Mario{y_position: y_position}}) when y_position >= 7, do: true

  # or when mario meets a bad guy
  def mario_dies?(%Game{
        current_position: current_position,
        level: level,
        mario: %Mario{y_position: y_position, x_position: x_position}
      }) do
    Level.has_bad_guy_on_postion?(level, current_position + x_position, y_position)
  end

  # TODO between levels animation
  def draw(%Game{state: :paused, current_animation: nil}) do
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
          current_animation: nil,
          level: level
        } = game
      ) do
    game
    |> current_game_pixels
    |> Mario.draw(mario)
    |> Level.draw(game, level)
  end

  def draw(%Game{current_animation: current_animation}) do
    Animation.draw(current_animation)
  end

  defp current_game_pixels(%Game{
         level: level,
         current_position: current_position,
         windows_shown: windows_shown
       }) do
    Enum.map(level.pixels, fn row ->
      Enum.slice(row, current_position, 8 * windows_shown)
    end)
  end
end
