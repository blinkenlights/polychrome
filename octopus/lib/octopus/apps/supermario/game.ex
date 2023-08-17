defmodule Octopus.Apps.Supermario.Game do
  @moduledoc """
  handles the game logic
  """
  alias __MODULE__
  alias Octopus.{Canvas, Font}
  alias Octopus.Apps.Supermario.{Animation, Level, Mario}
  alias Octopus.Apps.Supermario.Animation.{Completed, GameOver, Intro, MarioDies}

  @type t :: %__MODULE__{
          state: :starting | :running | :paused | :mario_dies | :gameover | :completed,
          current_position: integer(),
          windows_shown: integer(),
          last_ticker: Time.t(),
          last_move: Time.t(),
          level: Level.t(),
          mario: Mario.t(),
          current_animation: Animation.t() | nil,
          lives: integer(),
          layout: map()
        }
  defstruct [
    :state,
    :current_position,
    :last_ticker,
    :last_move,
    :windows_shown,
    :level,
    :mario,
    :current_animation,
    :lives,
    :score,
    :layout
  ]

  # micro seconds between two moves
  @update_interval_ms 10_000
  @move_interval_ms 100_000
  @intro_animation_ms 3_000_000
  @dying_animation_ms 3_000_000
  @pause_animation_ms 4_000_000
  @game_over_animation_ms 18_000_000
  # starting from window
  @windows_offset 0

  def new(%{windows_shown: windows_shown, side: side}) do
    level = Level.new()

    %Game{
      level: level,
      state: :starting,
      current_position: 0,
      last_ticker: Time.utc_now(),
      last_move: Time.utc_now(),
      windows_shown: windows_shown,
      mario: Mario.new(level.mario_start_y_position),
      current_animation: nil,
      lives: 3,
      score: 0,
      layout: layout(side)
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

  def tick(%Game{state: :starting, last_ticker: last_ticker} = game) do
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
      next_level = Level.next_level(level)

      {:ok,
       %Game{
         game
         | state: :running,
           level: next_level,
           last_ticker: now,
           current_position: 0,
           mario: Mario.new(next_level.mario_start_y_position),
           score: game.score + 20
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

  def tick(%Game{state: :gameover, current_animation: nil} = game) do
    {:ok,
     %Game{
       game
       | current_animation: GameOver.new(@windows_offset, 4), #game.windows_shown
         last_ticker: Time.utc_now()
     }}
  end

  def tick(%Game{state: :completed, current_animation: nil, score: score} = game) do
    score = score + 20

    {:ok,
     %Game{
       game
       | current_animation: Completed.new(@windows_offset, game.windows_shown, score),
         last_ticker: Time.utc_now(),
         score: score
     }}
  end

  def tick(%Game{state: state, last_ticker: last_ticker} = game)
      when state == :gameover or state == :completed do
    now = Time.utc_now()

    if Time.diff(now, last_ticker, :microsecond) > @game_over_animation_ms do
      {:gameover, game}
    else
      {:ok, game}
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

    {:ok, game}
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
      now = Time.utc_now()

      if Time.diff(now, game.last_move, :microsecond) > @move_interval_ms and
           Mario.can_move_right?(mario, game) do
        {:ok, %Game{game | current_position: current_position + 1, last_move: now}}
      else
        {:ok, game}
      end
    else
      if mario.x_position < 7 do
        {:ok, %Game{game | mario: Mario.move_right(mario, level)}}
      else
        if Level.last_level?(game.level) do
          {:game_over, %Game{game | state: :completed}}
        else
          {:ok, %Game{game | state: :paused, last_ticker: Time.utc_now()}}
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
    game =
      if Level.has_bad_guy_on_postion?(level, absolute_x_position, y_position) do
        %Game{
          game
          | level: Level.kill_bad_guy(level, absolute_x_position, y_position),
            score: game.score + 3
        }
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

  # last live: game over!!
  def mario_has_died(%Game{lives: 1} = game) do
    {:ok, %Game{game | state: :gameover}}
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

    {:ok,
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

  #  between levels animation
  def render_canvas(%Game{state: :paused, current_animation: nil, layout: layout}) do
    {:ok, %ExPng.Image{} = image} =
      ExPng.Image.from_file(Path.join([:code.priv_dir(:octopus), "images", "mario.png"]))

    Enum.map(0..7, fn y ->
      Enum.map(0..7, fn x ->
        <<r, g, b, _a>> = ExPng.Image.at(image, {x, y})
        [r, g, b]
      end)
    end)
    |> fill_canvas(layout.base_canvas, layout.playfield_base)
  end

  # draw current pixels of level and mario
  def render_canvas(
        %Game{
          mario: mario,
          current_animation: nil,
          level: level,
          layout: layout
        } = game
      ) do
    game
    |> current_game_pixels
    |> Mario.draw(mario)
    |> Level.draw(game, level)
    |> fill_canvas(layout.base_canvas, layout.playfield_base)
    # |> render_score(game)
  end

  def render_canvas(%Game{
    current_animation: %Animation{animation_type: animation_type} = current_animation}
  )
      when animation_type == :game_over or animation_type == :completed do
    Animation.draw(current_animation)
  end

  def render_canvas(%Game{current_animation: current_animation, layout: layout}) do
    fill_canvas(
      Animation.draw(current_animation),
      layout.base_canvas,
      layout.playfield_base
    )
  end

  defp render_score(canvas, %Game{layout: layout, score: score}) do
    [first, second] =
        score
        |> to_string()
        |> String.pad_leading(2, "0")
        |> String.to_charlist()

    font = Font.load("gunb")
    font_variant = 8
    Font.pipe_draw_char(font, second, font_variant, {layout.score_base, 0})
    |> (fn c ->
          unless first == ?0 do
            c |> Font.pipe_draw_char(font, first, font_variant, {layout.score_base - 8, 0})
          else
            c
          end
        end).()

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

  defp fill_canvas(visible_level_pixels, base_canvas, playfield_base) do
    canvas = Canvas.new(8, 8)
    {canvas, _} =
      Enum.reduce(visible_level_pixels, {canvas, 0}, fn row, {canvas, y} ->
        {canvas, _, y} =
          Enum.reduce(row, {canvas, 0, y}, fn [r, g, b], {canvas, x, y} ->
            canvas =
              Canvas.put_pixel(
                canvas,
                {x, y},
                {r, g, b}
              )

            {canvas, x + 1, y}
          end)

        {canvas, y + 1}
      end)
    Canvas.overlay(base_canvas, canvas, offset: {playfield_base, 0})
  end

  defp layout(:right) do
    %{
          base_canvas: Canvas.new(40, 8),
          score_base: 16,
          playfield_base: 8 * 4,
          playfield_channel: 5
    }
  end

  defp layout(:left) do
    %{
        base_canvas: Canvas.new(40, 8),
        core_base: 16,
          playfield_base: 0,
          playfield_channel: 6
      }
  end
end
