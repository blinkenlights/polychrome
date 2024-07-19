defmodule Octopus.Apps.Whackamole.Game do
  use Octopus.Params, prefix: :whackamole
  require Logger
  alias Octopus.{Canvas, Font, App, Animator, Transitions, Sprite, EventScheduler, InputAdapter}
  alias Octopus.Apps.Whackamole.Mole

  defstruct [
    :state,
    :animator,
    :tick,
    :score,
    :font,
    :lives,
    :moles,
    :last_mole,
    :difficulty,
    :whack_times,
    :tilt_start,
    :highscore
  ]

  # game_states [:intro, :playing, :game_over, :tilt]

  @font_name "cshk-Captain Sky Hawk (RARE)"
  @sprite_sheet "256-characters-original"
  @highscore_file "whackamole_highscore"
  # 56..59
  @mole_sprites 0..255

  @survived_color {255, 0, 0}

  def new() do
    {:ok, animator} = Animator.start_link(app_id: App.get_app_id())

    %__MODULE__{
      state: :intro,
      animator: animator,
      lives: 3,
      font: Font.load(@font_name),
      tick: 0,
      score: 0,
      difficulty: 1,
      last_mole: 0,
      moles: %{},
      whack_times: [],
      highscore: read_highscore()
    }
  end

  def tick(%__MODULE__{state: :intro} = game) do
    transition_fun = &Transitions.push(&1, &2, direction: :top, separation: 0)
    duration = 300

    case game.tick do
      3 ->
        whack =
          Canvas.new(6 * 8, 8)
          |> Canvas.put_string({0, 0}, " WHACK", game.font, 0)

        Animator.start_animation(game.animator, whack, {0, 0}, transition_fun, duration)
        next_tick(game)

      6 ->
        a =
          Canvas.new(3 * 8, 8)
          |> Canvas.put_string({0, 0}, "'EM", game.font, 1)

        Animator.start_animation(game.animator, a, {6 * 8, 0}, transition_fun, duration)
        next_tick(game)

      30 ->
        Animator.clear(game.animator, fade_out: 500)
        %__MODULE__{game | state: :playing, tick: 0}

      _ ->
        next_tick(game)
    end
  end

  def tick(%__MODULE__{state: :playing} = game) do
    game
    |> mole_survived?()
    |> case do
      %__MODULE__{lives: lives} = game when lives > 0 ->
        game
        |> check_tilt()
        |> maybe_add_mole()
        |> maybe_increase_difficulty()
        |> next_tick()

      _ ->
        %__MODULE__{game | state: :game_over, tick: 0}
    end
  end

  def tick(%__MODULE__{state: :game_over} = game) do
    transition_fun = &Transitions.push(&1, &2, direction: :top, separation: 0)
    duration = 300

    case game.tick do
      2 ->
        Animator.clear(game.animator, fade_out: 500)
        next_tick(game)

      7 ->
        game_over =
          Canvas.new(10 * 8, 8)
          |> Canvas.put_string({0, 0}, "GAME OVER", game.font, 1)

        Animator.start_animation(game.animator, game_over, {0, 0}, transition_fun, duration)
        next_tick(game)

      30 ->
        text = " SCORE #{game.score |> to_string()}"

        score =
          Canvas.new(10 * 8, 8)
          |> Canvas.put_string({0, 0}, text, game.font, 2)

        Animator.start_animation(game.animator, score, {0, 0}, transition_fun, duration)
        next_tick(game)

      50 ->
        canvas =
          if game.score > game.highscore do
            write_highscore(game.score)

            Canvas.new(10 * 8, 8)
            |> Canvas.put_string({0, 0}, "HIGHSCORE!", game.font, 0)
          else
            Canvas.new(10 * 8, 8)
            |> Canvas.put_string({0, 0}, " HIGH #{game.highscore}", game.font, 0)
          end

        Animator.start_animation(game.animator, canvas, {0, 0}, transition_fun, duration)

        next_tick(game)

      70 ->
        EventScheduler.game_finished()
        next_tick(game)

      _ ->
        next_tick(game)
    end
  end

  def tick(%__MODULE__{state: :tilt} = game) do
    duration = 1000

    case game.tick - game.tilt_start do
      1 ->
        tilt =
          Canvas.new(10 * 8, 8)
          |> Canvas.put_string({0, 0}, "   TILT!", game.font, 3)

        blank_canvas = Canvas.new(10 * 8, 8) |> Canvas.fill({0, 0, 0})

        transition_fun = &[&1, tilt, blank_canvas, tilt, blank_canvas, &2]
        Animator.start_animation(game.animator, tilt, {0, 0}, transition_fun, duration)

        next_tick(game)

      20 ->
        Animator.clear(game.animator, fade_out: 500)
        %__MODULE__{game | state: :playing}

      _ ->
        next_tick(game)
    end
  end

  def whack(%__MODULE__{state: :playing} = game, button_number) do
    whack_animation(game, button_number)

    if Map.has_key?(game.moles, button_number) do
      moles = Map.delete(game.moles, button_number)
      score = game.score + 1

      down_animation(game, button_number)

      %__MODULE__{game | moles: moles, score: score}
    else
      now = System.os_time(:millisecond)
      %__MODULE__{game | whack_times: [now | game.whack_times]}
    end
  end

  def whack(%__MODULE__{} = game, _), do: game

  def next_tick(%__MODULE__{tick: tick} = game) do
    %__MODULE__{game | tick: tick + 1}
  end

  def check_tilt(%__MODULE__{} = game) do
    tilt_duration_ms = param(:tilt_duration_ms, 1000)
    tilt_max = param(:tilt_max, 6)
    now = System.os_time(:millisecond)

    {_expired, active} =
      Enum.split_with(game.whack_times, fn time ->
        now - time > tilt_duration_ms
      end)

    case Enum.count(active) do
      count when count > tilt_max ->
        %__MODULE__{
          game
          | lives: game.lives - 1,
            whack_times: [],
            state: :tilt,
            tilt_start: game.tick
        }

      _ ->
        %__MODULE__{game | whack_times: active}
    end
  end

  def maybe_add_mole(%__MODULE__{} = game) do
    mole_delay_s = param(:mole_delay_s, 1.5)
    spread = 0.3
    value = mole_delay_s * 10 * game.difficulty
    diff = value * spread
    min = value - diff
    target = :rand.uniform() * diff + min

    if game.tick - game.last_mole > target do
      pannels_with_moles = Map.keys(game.moles)

      case Enum.to_list(0..9) -- pannels_with_moles do
        [] ->
          Logger.error("No free pannels")
          game

        free_pannels ->
          pannel = Enum.random(free_pannels)
          moles = Map.put(game.moles, pannel, Mole.new(pannel, game.tick))
          spawn_animation(game, pannel)

          %__MODULE__{game | moles: moles, last_mole: game.tick}
      end
    else
      game
    end
  end

  def maybe_increase_difficulty(%__MODULE__{} = game) do
    increment_difficulty_every_s = param(:increment_difficulty_every_s, 4)
    difficulty_decay = param(:difficulty_decay, 0.05)

    if rem(game.tick, increment_difficulty_every_s * 10) == 0 do
      difficulty =
        :math.exp(game.tick / increment_difficulty_every_s / 10 * difficulty_decay * -1)

      Logger.info("Difficulty increased from #{game.difficulty} to #{difficulty}")
      %__MODULE__{game | difficulty: difficulty}
    else
      game
    end
  end

  def mole_survived?(%__MODULE__{} = game) do
    mole_time_to_live_s = param(:mole_time_to_live_s, 7)

    {survived, active} =
      Enum.split_with(game.moles, fn {_, mole} ->
        game.tick - mole.start_tick > mole_time_to_live_s * 10 * game.difficulty
      end)

    survived
    |> Enum.each(fn {_, %Mole{} = mole} ->
      lost_animation(game, mole)
    end)

    moles = Enum.into(active, %{})

    %__MODULE__{game | moles: moles, lives: game.lives - Enum.count(survived)}
  end

  def lost_animation(%__MODULE__{} = game, %Mole{} = mole) do
    # Logger.info("LOST ANIMATION for mole #{mole.pannel} in tick #{game.tick}")
    red_canvas = Canvas.new(8, 8) |> Canvas.fill(@survived_color)
    blank_canvas = Canvas.new(8, 8) |> Canvas.fill({0, 0, 0})
    # transition_fn = &[&1, red_canvas, blank_canvas, red_canvas, blank_canvas, red_canvas, &2]

    transition_fn = fn canvas_sprite, _ ->
      blended = Canvas.blend(canvas_sprite, red_canvas, :multiply, 1)
      [canvas_sprite, blended, canvas_sprite, blended, canvas_sprite, blended, blank_canvas]
    end

    # transition_fn =&[&1, red_canvas, blank_canvas, red_canvas, blank_canvas, red_canvas, &2]
    lost_animation_duration_ms = param(:lost_animation_duration_ms, 500)

    Animator.start_animation(
      game.animator,
      blank_canvas,
      {mole.pannel * 8, 0},
      transition_fn,
      lost_animation_duration_ms
    )
  end

  def down_animation(%__MODULE__{} = game, pannel) do
    # Logger.info("WHACKAMOLE: WHACKED MOLE #{pannel}")
    blank_canvas = Canvas.new(8, 8) |> Canvas.fill({0, 0, 0})
    transition_fun = &Transitions.push(&1, &2, direction: :bottom, separation: 0)
    mole_spawn_duration_ms = param(:mole_spawn_duration_ms, 300) * game.difficulty

    Animator.start_animation(
      game.animator,
      blank_canvas,
      {pannel * 8, 0},
      transition_fun,
      mole_spawn_duration_ms
    )
  end

  def spawn_animation(%__MODULE__{} = game, pannel) do
    # Logger.info("WHACKAMOLE: SPAWN MOLE #{pannel}")
    show_hints_till = 50

    sprite_canvas = Sprite.load(@sprite_sheet, Enum.random(@mole_sprites))
    transition_fun = &Transitions.push(&1, &2, direction: :top, separation: 0)
    mole_spawn_duration_ms = param(:mole_spawn_duration_ms, 300) * game.difficulty

    if game.tick < show_hints_till do
      InputAdapter.send_light_event(pannel + 1, 1000)
    end

    Animator.start_animation(
      game.animator,
      sprite_canvas,
      {pannel * 8, 0},
      transition_fun,
      mole_spawn_duration_ms
    )
  end

  def whack_animation(%__MODULE__{} = game, pannel) do
    # Logger.info("WHACKAMOLE: WHACK #{pannel}")

    # todo convert to rgbw white
    whack_canvas =
      Canvas.new(8, 8)
      |> Canvas.fill({0, 64, 64})
      |> Canvas.put_pixel({0, 0}, {0, 0, 0})
      |> Canvas.put_pixel({0, 7}, {0, 0, 0})
      |> Canvas.put_pixel({7, 0}, {0, 0, 0})
      |> Canvas.put_pixel({7, 7}, {0, 0, 0})

    transition_fun = fn start, _ -> [start, whack_canvas, start] end
    whack_duration = param(:whack_duration, 100)

    Animator.start_animation(
      game.animator,
      whack_canvas,
      {pannel * 8, 0},
      transition_fun,
      whack_duration
    )

    InputAdapter.send_light_event(pannel + 1, 500)
  end

  def read_highscore() do
    highscore_path = File.cwd!() |> Path.join(@highscore_file)

    if File.exists?(highscore_path) do
      File.read!(highscore_path) |> String.to_integer()
    else
      write_highscore(0)
      0
    end
  end

  def write_highscore(score) do
    highscore_path = File.cwd!() |> Path.join(@highscore_file)
    File.write!(highscore_path, score |> to_string())
  end
end
