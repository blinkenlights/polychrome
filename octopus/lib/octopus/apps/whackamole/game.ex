defmodule Octopus.Apps.Whackamole.Game do
  use Octopus.Params, prefix: :whackamole
  alias Octopus.{Canvas, Font, Animator, Transitions, Sprite, InputAdapter}
  alias Octopus.Apps.Whackamole.Mole
  alias Octopus.Installation

  defstruct [
    :state,
    :score,
    :font,
    :lives,
    :moles,
    :difficulty,
    :whack_times,
    :highscore,
    :display_info,
    :panel_width,
    :panel_height,
    :active_animators,
    :panel_canvases,
    :display_canvas,
    :last_mole_spawn_time,
    # Track sprites for each panel
    :mole_sprites,
    # Double buffer system - background layer (red/green effects)
    :panel_background_canvases,
    # Double buffer system - foreground layer (mole sprites)
    :panel_foreground_canvases
  ]

  # game_states [:intro, :playing, :game_over, :tilt]

  @font_name "cshk-Captain Sky Hawk (RARE)"
  @sprite_sheet "256-characters-original"
  @highscore_file "whackamole_highscore"
  # 56..59
  @mole_sprites 0..255

  def new(display_info) do
    %__MODULE__{
      state: :intro,
      lives: 3,
      font: Font.load(@font_name),
      score: 0,
      difficulty: 1,
      moles: %{},
      whack_times: [],
      highscore: read_highscore(),
      display_info: display_info,
      panel_width: display_info.panel_width,
      panel_height: display_info.panel_height,
      active_animators: %{},
      panel_canvases: %{},
      display_canvas: Canvas.new(display_info.width, display_info.height),
      last_mole_spawn_time: System.os_time(:millisecond),
      mole_sprites: %{},
      panel_background_canvases: %{},
      panel_foreground_canvases: %{}
    }
  end

  def start_intro(game, app_pid) do
    # Start the intro sequence
    transition_fun = &Transitions.push(&1, &2, direction: :top, separation: 0)
    duration = 300

    whack =
      Canvas.new(6 * game.panel_width, game.panel_height)
      |> Canvas.put_string({0, 0}, " WHACK", game.font, 0)

    # Start "WHACK" animation
    Animator.animate(
      animation_id: {:intro_whack},
      app_pid: app_pid,
      canvas: whack,
      position: {0, 0},
      transition_fun: transition_fun,
      duration: duration,
      canvas_size: {6 * game.panel_width, game.panel_height},
      frame_rate: 60
    )

    # Schedule "'EM!" animation to start after "WHACK" completes
    :timer.send_after(duration + 100, {:start_intro_em})

    %{game | state: :intro}
  end

  def start_playing(game) do
    # Clear display and start playing
    blank_canvas = Canvas.new(game.display_info.width, game.display_info.height)
    send(self(), {:clear_display, blank_canvas})

    # Start mole spawning
    schedule_next_mole_spawn(game)

    %{game | state: :playing, active_animators: %{}, display_canvas: blank_canvas}
  end

  def start_game_over(game) do
    # Clear any remaining animators and start game over sequence
    clear_all_animators(game)
    start_game_over_animation(game, self())

    %{game | state: :game_over}
  end

  def start_tilt(game) do
    # Start tilt animation
    duration = 1000

    tilt =
      Canvas.new(Installation.num_panels() * game.panel_width, game.panel_height)
      |> Canvas.put_string({0, 0}, "   TILT!", game.font, 3)

    blank_canvas =
      Canvas.new(Installation.num_panels() * game.panel_width, game.panel_height)
      |> Canvas.fill({0, 0, 0})

    transition_fun = &[&1, tilt, blank_canvas, tilt, blank_canvas, &2]

    Animator.animate(
      animation_id: {:tilt},
      app_pid: self(),
      canvas: tilt,
      position: {0, 0},
      transition_fun: transition_fun,
      duration: duration,
      canvas_size: {Installation.num_panels() * game.panel_width, game.panel_height},
      frame_rate: 60
    )

    # Schedule end of tilt
    :timer.send_after(duration + 100, {:end_tilt})

    %{game | state: :tilt}
  end

  def end_tilt(game) do
    # Clear tilt animation
    clear_all_animators(game)
    blank_canvas = Canvas.new(game.display_info.width, game.display_info.height)
    send(self(), {:clear_display, blank_canvas})

    # Check if game should be over after tilt
    if game.lives <= 0 do
      # Game over - don't return to playing, go directly to game over
      send(self(), {:game_over})
      %{game | state: :game_over, active_animators: %{}, display_canvas: blank_canvas}
    else
      # Resume playing - resume mole spawning
      schedule_next_mole_spawn(game)
      %{game | state: :playing, active_animators: %{}, display_canvas: blank_canvas}
    end
  end

  def handle_whack(game, button_number) do
    case game.state do
      :playing ->
        if Map.has_key?(game.moles, button_number) do
          # Successful whack
          moles = Map.delete(game.moles, button_number)
          score = game.score + 1

          # Clear both foreground and background animations for this panel
          Animator.clear({:foreground_mole, button_number})
          Animator.clear({:background_effect, button_number})
          send(self(), {:clear_panel_layers, button_number})

          # Start success animation
          whack_success_animation(game, button_number)

          %{game | moles: moles, score: score}
        else
          # Missed whack - check for tilt
          whack_fail_animation(game, button_number, false)
          now = System.os_time(:millisecond)
          whack_times = [now | game.whack_times]

          updated_game = %{game | whack_times: whack_times}
          check_tilt(updated_game)
        end

      _ ->
        # Ignore whacks in other states
        game
    end
  end

  def handle_mole_warning(game, panel) do
    case game.state do
      :playing ->
        if Map.has_key?(game.moles, panel) do
          # Start warning animation - dramatic blinking without decrementing lives yet
          mole = game.moles[panel]
          warning_animation(game, mole)
          game
        else
          game
        end

      _ ->
        game
    end
  end

  def handle_mole_timeout(game, panel) do
    case game.state do
      :playing ->
        if Map.has_key?(game.moles, panel) do
          # Mole actually timed out - decrement lives and remove mole
          moles = Map.delete(game.moles, panel)
          lives = game.lives - 1

          # Clear both foreground and background animations for this panel
          Animator.clear({:foreground_mole, panel})
          Animator.clear({:background_effect, panel})
          send(self(), {:clear_panel_layers, panel})

          # Clear the stored mole sprite since the mole is gone
          send(self(), {:clear_mole_sprite, panel})

          updated_game = %{
            game
            | moles: moles,
              lives: lives
          }

          # Check if game over - give more time for any remaining animations
          if lives <= 0 do
            # Delay game over to allow any remaining animations to complete
            :timer.send_after(1000, {:game_over})
            updated_game
          else
            updated_game
          end
        else
          game
        end

      _ ->
        game
    end
  end

  def maybe_spawn_mole(game) do
    case game.state do
      :playing ->
        now = System.os_time(:millisecond)
        mole_delay_ms = get_mole_delay_ms(game.difficulty)

        if now - game.last_mole_spawn_time > mole_delay_ms do
          panels_with_moles = Map.keys(game.moles)
          free_panels = Enum.to_list(0..(Installation.num_panels() - 1)) -- panels_with_moles

          case free_panels do
            [] ->
              game

            _ ->
              panel = Enum.random(free_panels)
              mole = Mole.new(panel, now)
              moles = Map.put(game.moles, panel, mole)

              # Start spawn animation
              spawn_animation(game, panel)

              # Schedule mole warning (3 seconds before timeout)
              mole_timeout_ms = get_mole_timeout_ms(game.difficulty)
              # Start warning 3s before timeout
              warning_delay_ms = mole_timeout_ms - 3000

              if warning_delay_ms > 0 do
                :timer.send_after(warning_delay_ms, {:mole_warning, panel})
              else
                # If timeout is less than 3s, start warning immediately
                :timer.send_after(100, {:mole_warning, panel})
              end

              # Schedule actual mole timeout
              :timer.send_after(mole_timeout_ms, {:mole_timeout, panel})

              %{game | moles: moles, last_mole_spawn_time: now}
          end
        else
          game
        end

      _ ->
        game
    end
  end

  def schedule_next_mole_spawn(game) do
    delay_ms = get_mole_spawn_interval_ms(game.difficulty)
    :timer.send_after(delay_ms, {:spawn_mole})
    :ok
  end

  defp check_tilt(game) do
    tilt_duration_ms = param(:tilt_duration_ms, 1000)
    tilt_max = param(:tilt_max, 6)
    now = System.os_time(:millisecond)

    {_expired, active} =
      Enum.split_with(game.whack_times, fn time ->
        now - time > tilt_duration_ms
      end)

    case Enum.count(active) do
      count when count > tilt_max ->
        # Start tilt
        lives = game.lives - 1
        updated_game = %{game | lives: lives, whack_times: []}

        # Always start tilt animation - end_tilt will check if game should be over
        send(self(), {:start_tilt})
        updated_game

      _ ->
        %{game | whack_times: active}
    end
  end

  defp get_mole_delay_ms(difficulty) do
    base_delay = param(:mole_delay_s, 1.5) * 1000
    round(base_delay * difficulty)
  end

  defp get_mole_timeout_ms(difficulty) do
    base_timeout = param(:mole_time_to_live_s, 7) * 1000
    round(base_timeout * difficulty)
  end

  defp get_mole_spawn_interval_ms(difficulty) do
    # How often to check for spawning new moles
    base_interval = 500
    round(base_interval * difficulty)
  end

  defp spawn_animation(game, panel) do
    show_hints_till = 50
    current_time = System.os_time(:millisecond)

    sprite_canvas = Sprite.load(@sprite_sheet, Enum.random(@mole_sprites))
    transition_fun = &Transitions.push(&1, &2, direction: :top, separation: 0)
    mole_spawn_duration_ms = param(:mole_spawn_duration_ms, 300) * game.difficulty

    # Store the sprite for this panel so we can use it in down animation
    send(self(), {:store_mole_sprite, panel, sprite_canvas})

    # Show light hint for early game
    if current_time - game.last_mole_spawn_time < show_hints_till * 1000 do
      InputAdapter.send_light_event(panel + 1, 1000)
    end

    # Use foreground layer for mole sprites
    Animator.animate(
      animation_id: {:foreground_mole, panel},
      app_pid: self(),
      canvas: sprite_canvas,
      position: {0, 0},
      transition_fun: transition_fun,
      duration: mole_spawn_duration_ms,
      canvas_size: {game.panel_width, game.panel_height},
      frame_rate: 60
    )

    :ok
  end

  defp warning_animation(game, mole) do
    blank_canvas = Canvas.new(game.panel_width, game.panel_height) |> Canvas.fill({0, 0, 0})
    yellow_canvas = background_canvas(game, 60, 50, 70)

    # Get the stored mole sprite for this panel, or fallback to random
    sprite_canvas =
      Map.get(game.mole_sprites, mole.panel) ||
        Sprite.load(@sprite_sheet, Enum.random(@mole_sprites))

    # Create a proper accelerating blink pattern
    # Start with slow blinks (long on/off periods) and progressively get faster
    foreground_transition_fn = fn _start, _ ->
      # Create frames with decreasing blink duration
      # Early frames: long on/off periods (slow blinks)
      # Later frames: short on/off periods (fast blinks)
      slow_blinks = [
        # 4 frames ON
        sprite_canvas,
        sprite_canvas,
        sprite_canvas,
        sprite_canvas,
        # 4 frames OFF
        blank_canvas,
        blank_canvas,
        blank_canvas,
        blank_canvas,
        # 4 frames ON
        sprite_canvas,
        sprite_canvas,
        sprite_canvas,
        sprite_canvas,
        # 4 frames OFF
        blank_canvas,
        blank_canvas,
        blank_canvas,
        blank_canvas
      ]

      medium_blinks = [
        # 3 frames ON
        sprite_canvas,
        sprite_canvas,
        sprite_canvas,
        # 3 frames OFF
        blank_canvas,
        blank_canvas,
        blank_canvas,
        # 3 frames ON
        sprite_canvas,
        sprite_canvas,
        sprite_canvas,
        # 3 frames OFF
        blank_canvas,
        blank_canvas,
        blank_canvas,
        # 3 frames ON
        sprite_canvas,
        sprite_canvas,
        sprite_canvas,
        # 3 frames OFF
        blank_canvas,
        blank_canvas,
        blank_canvas
      ]

      fast_blinks = [
        # 2 frames ON
        sprite_canvas,
        sprite_canvas,
        # 2 frames OFF
        blank_canvas,
        blank_canvas,
        # 2 frames ON
        sprite_canvas,
        sprite_canvas,
        # 2 frames OFF
        blank_canvas,
        blank_canvas,
        # 2 frames ON
        sprite_canvas,
        sprite_canvas,
        # 2 frames OFF
        blank_canvas,
        blank_canvas,
        # 2 frames ON
        sprite_canvas,
        sprite_canvas,
        # 2 frames OFF
        blank_canvas,
        blank_canvas
      ]

      rapid_blinks = [
        # 1 frame ON, 1 frame OFF
        sprite_canvas,
        blank_canvas,
        # 1 frame ON, 1 frame OFF
        sprite_canvas,
        blank_canvas,
        # 1 frame ON, 1 frame OFF
        sprite_canvas,
        blank_canvas,
        # 1 frame ON, 1 frame OFF
        sprite_canvas,
        blank_canvas,
        # 1 frame ON, 1 frame OFF
        sprite_canvas,
        blank_canvas,
        # 1 frame ON, 1 frame OFF
        sprite_canvas,
        blank_canvas,
        # 1 frame ON, 1 frame OFF
        sprite_canvas,
        blank_canvas,
        # 1 frame ON, 1 frame OFF
        sprite_canvas,
        blank_canvas
      ]

      # Combine all sequences for accelerating effect
      slow_blinks ++ medium_blinks ++ fast_blinks ++ rapid_blinks ++ [blank_canvas]
    end

    # Fixed 3 second warning
    warning_animation_duration_ms = 3000

    # Add static yellow background
    Animator.animate(
      animation_id: {:background_effect, mole.panel},
      app_pid: self(),
      canvas: yellow_canvas,
      position: {0, 0},
      # Static - no transition
      transition_fun: fn _start, target -> [target] end,
      duration: warning_animation_duration_ms,
      canvas_size: {game.panel_width, game.panel_height},
      frame_rate: 60
    )

    # Animate the mole sprite blinking with accelerating pattern
    Animator.animate(
      animation_id: {:foreground_mole, mole.panel},
      app_pid: self(),
      # Start with mole visible
      canvas: sprite_canvas,
      position: {0, 0},
      transition_fun: foreground_transition_fn,
      duration: warning_animation_duration_ms,
      canvas_size: {game.panel_width, game.panel_height},
      frame_rate: 60
    )
  end

  defp down_animation(game, panel) do
    # Get the stored mole sprite for this panel, or fallback to random
    sprite_canvas =
      Map.get(game.mole_sprites, panel) || Sprite.load(@sprite_sheet, Enum.random(@mole_sprites))

    blank_canvas = Canvas.new(game.panel_width, game.panel_height) |> Canvas.fill({0, 0, 0})

    transition_fun = fn _start_canvas, target_canvas ->
      # Animate mole sprite going down (push down transition)
      Transitions.push(sprite_canvas, target_canvas, direction: :bottom, separation: 0)
    end

    # Separate parameter for down animation
    mole_down_duration_ms = param(:mole_down_duration_ms, 400)

    # Use foreground layer for mole down animation
    Animator.animate(
      animation_id: {:foreground_mole, panel},
      app_pid: self(),
      canvas: blank_canvas,
      position: {0, 0},
      transition_fun: transition_fun,
      duration: mole_down_duration_ms,
      canvas_size: {game.panel_width, game.panel_height},
      frame_rate: 60
    )

    # Clean up the stored sprite
    send(self(), {:clear_mole_sprite, panel})
  end

  defp whack_success_animation(game, panel) do
    # Green background effect on background layer
    green_canvas = background_canvas(game, 120, 50, 70)
    blank_canvas = Canvas.new(game.panel_width, game.panel_height) |> Canvas.fill({0, 0, 0})

    # Green flash effect on background layer
    green_transition_fun = fn _start, _ ->
      [blank_canvas, green_canvas, green_canvas, blank_canvas]
    end

    green_duration = 400

    # Start background green flash effect
    Animator.animate(
      animation_id: {:background_effect, panel},
      app_pid: self(),
      canvas: blank_canvas,
      position: {0, 0},
      transition_fun: green_transition_fun,
      duration: green_duration,
      canvas_size: {game.panel_width, game.panel_height},
      frame_rate: 60
    )

    # Start mole down animation simultaneously on foreground layer
    down_animation(game, panel)

    InputAdapter.send_light_event(panel + 1, 500)
  end

  defp whack_fail_animation(game, panel, _hit?) do
    # Red background effect on background layer
    red_canvas = background_canvas(game, 0, 50, 70)
    blank_canvas = Canvas.new(game.panel_width, game.panel_height) |> Canvas.fill({0, 0, 0})

    transition_fun = fn _start, _ -> [blank_canvas, red_canvas, blank_canvas] end
    whack_duration = param(:whack_duration, 300)

    Animator.animate(
      animation_id: {:background_effect, panel},
      app_pid: self(),
      canvas: blank_canvas,
      position: {0, 0},
      transition_fun: transition_fun,
      duration: whack_duration,
      canvas_size: {game.panel_width, game.panel_height},
      frame_rate: 60
    )

    InputAdapter.send_light_event(panel + 1, 500)
  end

  defp start_game_over_animation(game, app_pid) do
    transition_fun = &Transitions.push(&1, &2, direction: :top, separation: 0)
    duration = 300

    game_over =
      Canvas.new(Installation.num_panels() * game.panel_width, game.panel_height)
      |> Canvas.put_string({0, 0}, "GAME OVER", game.font, 1)

    Animator.animate(
      animation_id: {:game_over},
      app_pid: app_pid,
      canvas: game_over,
      position: {0, 0},
      transition_fun: transition_fun,
      duration: duration,
      canvas_size: {Installation.num_panels() * game.panel_width, game.panel_height},
      frame_rate: 60
    )

    # Schedule score animation
    :timer.send_after(duration + 1000, {:start_score_animation})
  end

  defp clear_all_animators(game) do
    # Clear old-style tracked animators
    Enum.each(Map.keys(game.active_animators), fn animation_id ->
      Animator.clear(animation_id)
    end)

    # Clear all mole-related animations for all panels
    for panel <- 0..(Installation.num_panels() - 1) do
      # Clear foreground mole animations (spawn, warning, down)
      Animator.clear({:foreground_mole, panel})
      # Clear background effect animations (success, fail, warning)
      Animator.clear({:background_effect, panel})
    end

    # Clear any intro/game-over animations that might be running
    Animator.clear({:intro_whack})
    Animator.clear({:intro_em})
    Animator.clear({:game_over})
    Animator.clear({:score})
    Animator.clear({:highscore})
    Animator.clear({:tilt})

    # Clear the display
    blank_canvas = Canvas.new(game.display_info.width, game.display_info.height)
    send(self(), {:clear_display, blank_canvas})

    :ok
  end

  defp background_canvas(game, h, s, v) do
    %Chameleon.RGB{r: r, g: g, b: b} = Chameleon.HSV.to_rgb(%Chameleon.HSV{h: h, s: s, v: v})

    Canvas.new(game.panel_width, game.panel_height)
    |> Canvas.fill({r, g, b})
    |> Canvas.put_pixel({0, 0}, {0, 0, 0})
    |> Canvas.put_pixel({0, game.panel_height - 1}, {0, 0, 0})
    |> Canvas.put_pixel({game.panel_width - 1, 0}, {0, 0, 0})
    |> Canvas.put_pixel({game.panel_width - 1, game.panel_height - 1}, {0, 0, 0})
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
