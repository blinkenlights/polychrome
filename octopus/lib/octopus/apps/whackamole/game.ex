defmodule Octopus.Apps.Whackamole.Game do
  require Logger
  alias Octopus.{Canvas, Font, App, Animator, Transitions, Sprite, EventScheduler}
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
    :difficulty
  ]

  @game_states [:intro, :playing, :game_over]

  @font_name "cshk-Captain Sky Hawk (RARE)"
  @sprite_sheet "256-characters-original"
  # 56..59
  @mole_sprites 0..255

  @mole_delay_s 2
  @mole_spawn_duration_ms 300
  @mole_time_to_live_s 3
  @lost_animation_duration_ms 500
  @game_over_fade_out_ms 500
  @whack_duration_ms 100

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
      moles: %{}
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

      # 9 ->
      #   mole =
      #     Canvas.new(4 * 8, 8)
      #     |> Canvas.put_string({0, 0}, "MOLE", game.font, 2)

      # Animator.start_animation(game.animator, mole, {6 * 8, 0}, transition_fun, duration)
      # next_tick(game)

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

      20 ->
        score =
          Canvas.new(10 * 8, 8)
          |> Canvas.put_string({24, 0}, game.score |> to_string(), game.font, 1)

        Animator.start_animation(game.animator, score, {0, 0}, transition_fun, duration)
        next_tick(game)

      40 ->
        EventScheduler.game_finished()
        next_tick(game)

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
      game
    end
  end

  def whack(%__MODULE__{} = game, _), do: game

  def next_tick(%__MODULE__{tick: tick} = game) do
    %__MODULE__{game | tick: tick + 1}
  end

  def maybe_add_mole(%__MODULE__{} = game) do
    if game.tick - game.last_mole > @mole_delay_s * 10 * game.difficulty do
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

  def maybe_increase_difficulty(%__MODULE__{difficulty: difficulty, tick: tick} = game) do
    # based on score, increase difficulty
    # difficulty should influence the mole duration (animation speed and delay) as well as the frequency
    game
  end

  def mole_survived?(%__MODULE__{} = game) do
    {survived, active} =
      Enum.split_with(game.moles, fn {_, mole} ->
        game.tick - mole.start_tick > @mole_time_to_live_s * 10 * game.difficulty
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
    transition_fn = &[&1, red_canvas, blank_canvas, red_canvas, blank_canvas, red_canvas, &2]
    duration = @lost_animation_duration_ms

    Animator.start_animation(
      game.animator,
      blank_canvas,
      {mole.pannel * 8, 0},
      transition_fn,
      duration
    )
  end

  def down_animation(%__MODULE__{} = game, pannel) do
    # Logger.info("WHACKAMOLE: WHACKED MOLE #{pannel}")
    blank_canvas = Canvas.new(8, 8) |> Canvas.fill({0, 0, 0})
    transition_fun = &Transitions.push(&1, &2, direction: :bottom, separation: 0)
    duration = @mole_spawn_duration_ms * game.difficulty

    Animator.start_animation(
      game.animator,
      blank_canvas,
      {pannel * 8, 0},
      transition_fun,
      duration
    )
  end

  def spawn_animation(%__MODULE__{} = game, pannel) do
    # Logger.info("WHACKAMOLE: SPAWN MOLE #{pannel}")

    sprite_canvas = Sprite.load(@sprite_sheet, Enum.random(@mole_sprites))
    transition_fun = &Transitions.push(&1, &2, direction: :top, separation: 0)
    duration = @mole_spawn_duration_ms * game.difficulty

    Animator.start_animation(
      game.animator,
      sprite_canvas,
      {pannel * 8, 0},
      transition_fun,
      duration
    )
  end

  def whack_animation(%__MODULE__{} = game, pannel) do
    # Logger.info("WHACKAMOLE: WHACK #{pannel}")

    # todo convert to rgbw white
    whack_canvas = Canvas.new(8, 8) |> Canvas.fill({255, 255, 255})
    transition_fun = fn start, _ -> [start, whack_canvas, start] end
    duration = @whack_duration_ms

    Animator.start_animation(
      game.animator,
      whack_canvas,
      {pannel * 8, 0},
      transition_fun,
      duration
    )
  end
end
