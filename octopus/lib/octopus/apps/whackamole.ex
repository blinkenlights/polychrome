defmodule Octopus.Apps.Whackamole do
  use Octopus.App, category: :game
  require Logger

  alias Octopus.Events.Event.Input, as: InputEvent
  alias Octopus.Canvas
  alias Octopus.Font
  alias Octopus.Apps.Whackamole.Game
  alias Octopus.Animator
  alias Octopus.Transitions
  alias Octopus.Installation

  defmodule State do
    defstruct [:game, :display_info]
  end

  def name(), do: "Whack'em"

  def icon(), do: Canvas.from_string("W", Font.load("cshk-Captain Sky Hawk (RARE)"), 3)

  def compatible?() do
    # Game works with any number of panels >= 3 for meaningful gameplay
    # and requires 8x8 pixel panels for proper mole sprite display
    Installation.num_panels() >= 3 and
      Installation.panel_width() == 8 and
      Installation.panel_height() == 8
  end

  def app_init(_) do
    # Configure display using modern unified API - adjacent layout for whackamole panels
    Octopus.App.configure_display(layout: :adjacent_panels)
    Octopus.App.subscribe_to_button_events()

    # Get display info for the game to use
    display_info = Octopus.App.get_display_info()

    game = Game.new(display_info)

    # Start the intro sequence immediately and update the game state
    updated_game = Game.start_intro(game, self())

    state = %State{
      game: updated_game,
      display_info: display_info
    }

    {:ok, state}
  end

  def handle_info({:intro_complete}, %State{} = state) do
    # Transition from intro to playing state
    updated_game = Game.start_playing(state.game)
    {:noreply, %{state | game: updated_game}}
  end

  def handle_info({:game_over}, %State{} = state) do
    # Transition to game over state
    updated_game = Game.start_game_over(state.game)
    {:noreply, %{state | game: updated_game}}
  end

  def handle_info({:start_tilt}, %State{} = state) do
    # Start tilt sequence
    updated_game = Game.start_tilt(state.game)
    {:noreply, %{state | game: updated_game}}
  end

  def handle_info({:end_tilt}, %State{} = state) do
    # End tilt and return to playing
    updated_game = Game.end_tilt(state.game)
    {:noreply, %{state | game: updated_game}}
  end

  def handle_info({:mole_timeout, panel}, %State{} = state) do
    # Handle mole timeout
    updated_game = Game.handle_mole_timeout(state.game, panel)
    {:noreply, %{state | game: updated_game}}
  end

  def handle_info({:mole_warning, panel}, %State{} = state) do
    # Handle mole warning - start dramatic blinking animation
    updated_game = Game.handle_mole_warning(state.game, panel)
    {:noreply, %{state | game: updated_game}}
  end

  def handle_info({:spawn_mole}, %State{} = state) do
    # Spawn a new mole
    updated_game = Game.maybe_spawn_mole(state.game)

    # Schedule next mole spawn
    Game.schedule_next_mole_spawn(updated_game)

    {:noreply, %{state | game: updated_game}}
  end

  def handle_info({:store_mole_sprite, panel, sprite_canvas}, %State{} = state) do
    # Store the mole sprite for this panel
    updated_game = %{
      state.game
      | mole_sprites: Map.put(state.game.mole_sprites, panel, sprite_canvas)
    }

    {:noreply, %{state | game: updated_game}}
  end

  def handle_info({:clear_mole_sprite, panel}, %State{} = state) do
    # Clear the stored mole sprite for this panel
    updated_game = %{
      state.game
      | mole_sprites: Map.delete(state.game.mole_sprites, panel)
    }

    {:noreply, %{state | game: updated_game}}
  end

  def handle_info({:clear_display, canvas}, %State{} = state) do
    # Clear the display with the provided blank canvas
    Octopus.App.update_display(canvas, :rgb, easing_interval: 0)

    # Update the game state to reflect the cleared display
    updated_game = %{state.game | display_canvas: canvas, panel_canvases: %{}}
    {:noreply, %{state | game: updated_game}}
  end

  def handle_info({:clear_panel_canvas, panel}, %State{} = state) do
    # Clear the specific panel canvas
    updated_state = clear_panel_canvas(state, panel)
    {:noreply, updated_state}
  end

  def handle_info({:clear_panel_layers, panel}, %State{} = state) do
    # Clear both background and foreground layers for this panel
    updated_state = clear_panel_layers(state, panel)
    {:noreply, updated_state}
  end

  def handle_info({:start_intro_em}, %State{} = state) do
    # Start the "'EM!" animation
    game = state.game
    transition_fun = &Transitions.push(&1, &2, direction: :top, separation: 0)
    duration = 300

    a =
      Canvas.new(4 * game.panel_width, game.panel_height)
      |> Canvas.put_string({0, 0}, "'EM!", game.font, 1)

    Animator.animate(
      animation_id: {:intro_em},
      app_pid: self(),
      canvas: a,
      position: {0, 0},
      transition_fun: transition_fun,
      duration: duration,
      canvas_size: {4 * game.panel_width, game.panel_height},
      frame_rate: 60
    )

    # Schedule intro completion - keep text visible for 1 second after animation finishes
    :timer.send_after(duration + 1000, {:intro_complete})

    {:noreply, state}
  end

  def handle_info({:start_score_animation}, %State{} = state) do
    # Start score animation
    game = state.game
    transition_fun = &Transitions.push(&1, &2, direction: :top, separation: 0)
    duration = 300

    text = " SCORE #{game.score |> to_string()}"

    score =
      Canvas.new(state.game.display_info.num_panels * game.panel_width, game.panel_height)
      |> Canvas.put_string({0, 0}, text, game.font, 2)

    Animator.animate(
      animation_id: {:score},
      app_pid: self(),
      canvas: score,
      position: {0, 0},
      transition_fun: transition_fun,
      duration: duration,
      canvas_size: {state.game.display_info.num_panels * game.panel_width, game.panel_height},
      frame_rate: 60
    )

    # Schedule highscore animation
    :timer.send_after(duration + 1000, {:start_highscore_animation})

    {:noreply, state}
  end

  def handle_info({:start_highscore_animation}, %State{} = state) do
    # Start highscore animation
    game = state.game
    transition_fun = &Transitions.push(&1, &2, direction: :top, separation: 0)
    duration = 300

    canvas =
      if game.score > game.highscore do
        Game.write_highscore(game.score)

        Canvas.new(state.game.display_info.num_panels * game.panel_width, game.panel_height)
        |> Canvas.put_string({0, 0}, "HI-SCORE!", game.font, 0)
      else
        Canvas.new(state.game.display_info.num_panels * game.panel_width, game.panel_height)
        |> Canvas.put_string({0, 0}, "HI #{game.highscore}", game.font, 0)
      end

    Animator.animate(
      animation_id: {:highscore},
      app_pid: self(),
      canvas: canvas,
      position: {0, 0},
      transition_fun: transition_fun,
      duration: duration,
      canvas_size: {state.game.display_info.num_panels * game.panel_width, game.panel_height},
      frame_rate: 60
    )

    # Schedule game over completion
    :timer.send_after(duration + 1000, {:game_over_complete})

    {:noreply, state}
  end

  def handle_info({:game_over_complete}, %State{} = state) do
    # Game over sequence complete
    Octopus.KioskModeManager.game_finished()
    {:noreply, state}
  end

  def handle_info({:animator_update, animation_id, canvas, frame_status}, %State{} = state) do
    # Handle canvas updates from the Animator module with animation identification
    updated_state =
      case animation_id do
        {:background_effect, panel} ->
          update_panel_background_canvas(state, panel, canvas, frame_status)

        {:foreground_mole, panel} ->
          update_panel_foreground_canvas(state, panel, canvas, frame_status)

        {:intro_whack} ->
          # Handle intro "WHACK" text - overlay on existing display
          overlay_on_display(state, canvas, {0, 0}, frame_status)

        {:intro_em} ->
          # Handle intro "'EM!" text - overlay after "WHACK"
          panel_width = state.display_info.panel_width
          overlay_on_display(state, canvas, {6 * panel_width, 0}, frame_status)

        {:game_over} ->
          # Handle game over text - full screen display
          Octopus.App.update_display(canvas, :rgb, easing_interval: 0)
          state

        {:score} ->
          # Handle score text - full screen display
          Octopus.App.update_display(canvas, :rgb, easing_interval: 0)
          state

        {:highscore} ->
          # Handle highscore text - full screen display
          Octopus.App.update_display(canvas, :rgb, easing_interval: 0)
          state

        {:tilt} ->
          # Handle tilt text - full screen display
          Octopus.App.update_display(canvas, :rgb, easing_interval: 0)
          state

        _ ->
          # For unknown animations, just update display directly
          Octopus.App.update_display(canvas, :rgb, easing_interval: 0)
          state
      end

    {:noreply, updated_state}
  end

  def handle_info(msg, %State{} = state) do
    Logger.warning("Unexpected message in WhackAMole: #{inspect(msg)}")
    {:noreply, state}
  end

  def handle_event(
        %InputEvent{type: :button, action: :press, button: button},
        %State{} = state
      ) do
    # Check if button is within valid range for current installation
    if button >= 1 and button <= Installation.num_panels() do
      button_number = button - 1
      updated_game = Game.handle_whack(state.game, button_number)
      {:noreply, %State{state | game: updated_game}}
    else
      # Button outside valid range - ignore
      {:noreply, state}
    end
  end

  def handle_event(%InputEvent{}, %State{} = state) do
    {:noreply, state}
  end

  def handle_event(_event, state) do
    {:noreply, state}
  end

  defp update_panel_background_canvas(state, panel, canvas, _frame_status) do
    # Update the background canvas for this panel
    game = state.game
    updated_background_canvases = Map.put(game.panel_background_canvases, panel, canvas)

    # Compose the full display from background + foreground layers
    new_display_canvas =
      compose_layered_display(
        updated_background_canvases,
        game.panel_foreground_canvases,
        state.display_info
      )

    # Update display
    Octopus.App.update_display(new_display_canvas, :rgb, easing_interval: 0)

    # Update game state
    updated_game = %{
      game
      | panel_background_canvases: updated_background_canvases,
        display_canvas: new_display_canvas
    }

    %{state | game: updated_game}
  end

  defp update_panel_foreground_canvas(state, panel, canvas, _frame_status) do
    # Update the foreground canvas for this panel
    game = state.game
    updated_foreground_canvases = Map.put(game.panel_foreground_canvases, panel, canvas)

    # Compose the full display from background + foreground layers
    new_display_canvas =
      compose_layered_display(
        game.panel_background_canvases,
        updated_foreground_canvases,
        state.display_info
      )

    # Update display
    Octopus.App.update_display(new_display_canvas, :rgb, easing_interval: 0)

    # Update game state
    updated_game = %{
      game
      | panel_foreground_canvases: updated_foreground_canvases,
        display_canvas: new_display_canvas
    }

    %{state | game: updated_game}
  end

  defp compose_layered_display(background_canvases, foreground_canvases, display_info) do
    # Create blank canvas
    display_canvas = Canvas.new(display_info.width, display_info.height)

    # Get all panels that have either background or foreground content
    all_panels =
      MapSet.union(
        MapSet.new(Map.keys(background_canvases)),
        MapSet.new(Map.keys(foreground_canvases))
      )

    # Compose each panel by layering background + foreground
    Enum.reduce(all_panels, display_canvas, fn panel_index, acc ->
      x_offset = panel_index * display_info.panel_width

      # Start with background layer (if exists)
      panel_canvas =
        case Map.get(background_canvases, panel_index) do
          nil -> Canvas.new(display_info.panel_width, display_info.panel_height)
          bg_canvas -> bg_canvas
        end

      # Composite foreground layer with background, treating black pixels as transparent
      panel_canvas =
        case Map.get(foreground_canvases, panel_index) do
          nil ->
            panel_canvas

          fg_canvas ->
            # Composite foreground onto background, treating black as transparent
            composite_with_transparency(panel_canvas, fg_canvas)
        end

      # Overlay the composed panel onto the display
      Canvas.overlay(acc, panel_canvas, offset: {x_offset, 0})
    end)
  end

  # Composite foreground canvas onto background canvas, treating black pixels as transparent
  defp composite_with_transparency(background_canvas, foreground_canvas) do
    # Create a new canvas with the background as base
    result_canvas = Canvas.new(background_canvas.width, background_canvas.height)

    # Copy background first
    result_canvas = Canvas.overlay(result_canvas, background_canvas, offset: {0, 0})

    # For each pixel in foreground, only copy if it's not black
    for y <- 0..(foreground_canvas.height - 1),
        x <- 0..(foreground_canvas.width - 1),
        reduce: result_canvas do
      acc ->
        fg_pixel = Canvas.get_pixel(foreground_canvas, {x, y})

        case fg_pixel do
          # Black pixel - transparent, don't copy
          {0, 0, 0} -> acc
          # Non-black pixel - copy it
          _ -> Canvas.put_pixel(acc, {x, y}, fg_pixel)
        end
    end
  end

  defp clear_panel_canvas(state, panel) do
    # Remove both background and foreground layers for this panel (delegate to clear_panel_layers)
    clear_panel_layers(state, panel)
  end

  defp clear_panel_layers(state, panel) do
    # Remove both background and foreground layers for this panel
    game = state.game
    updated_background_canvases = Map.delete(game.panel_background_canvases, panel)
    updated_foreground_canvases = Map.delete(game.panel_foreground_canvases, panel)

    # Compose the full display from remaining layers
    new_display_canvas =
      compose_layered_display(
        updated_background_canvases,
        updated_foreground_canvases,
        state.display_info
      )

    # Update display
    Octopus.App.update_display(new_display_canvas, :rgb, easing_interval: 0)

    # Update game state
    updated_game = %{
      game
      | panel_background_canvases: updated_background_canvases,
        panel_foreground_canvases: updated_foreground_canvases,
        display_canvas: new_display_canvas
    }

    %{state | game: updated_game}
  end

  defp overlay_on_display(state, canvas, {x, y}, _frame_status) do
    # For intro text, overlay on the current display canvas
    game = state.game
    new_display_canvas = Canvas.overlay(game.display_canvas, canvas, offset: {x, y})

    # Update display with the overlaid canvas
    Octopus.App.update_display(new_display_canvas, :rgb, easing_interval: 0)

    # Update game state
    updated_game = %{game | display_canvas: new_display_canvas}
    %{state | game: updated_game}
  end
end
