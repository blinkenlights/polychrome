defmodule Octopus.Apps.SlotMachine do
  @moduledoc """
  Slot Machine App for Octopus

  The display is split into 3 sections, each section operates independently:
  - Section 0: Panels 1-3 (0-indexed as 0,1,2) - Slots 0,1,2
  - Section 1: Panels 5-7 (0-indexed as 4,5,6) - Slots 0,1,2
  - Section 2: Panels 9-11 (0-indexed as 8,9,10) - Slots 0,1,2

  Each slot can be running (animating) or stopped.
  Buttons 1-3, 5-7, 9-11 control the corresponding slots.
  When all slots in a section show the same sprite, it's a win.
  """

  use Octopus.App, category: :game
  require Logger

  alias Octopus.{Sprite, Canvas, Transitions, Animator}
  alias Octopus.Events.Event.Input, as: InputEvent

  # Default animation duration (milliseconds)
  @default_animation_duration 600
  # Speed variation range (+/- milliseconds)
  @speed_variation 100
  # Blink speed when winning
  @blink_interval 300
  # Number of blinks on win
  @blink_count 5

  # Sprite groups with at least 6 sprites for slot machine
  @sprite_groups [
    aliens: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
    clicky: [16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27],
    corrosion: [28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43],
    spooky: [44, 45, 46, 47, 48, 49, 50, 51],
    spookyfast: [52, 53, 54, 55],
    stars1: [56, 57, 58, 59, 60],
    stars2: [61, 62, 63, 64, 65, 66],
    stars3: [67, 68, 69, 70],
    stars4: [71, 72, 73, 74, 75]
  ]

  # 8x8 sprite sheet path
  @sprite_sheet "256-characters-original"

  # Generate random animation duration for a slot (600ms +/- 100ms)
  defp generate_slot_animation_duration() do
    variation = :rand.uniform(@speed_variation * 2) - @speed_variation
    max(100, @default_animation_duration + variation)
  end

  defmodule State do
    defstruct [
      :sprite_groups,
      # Sprite group and randomized order for each section
      :section_sprite_groups,
      # Current sprite index for each slot in each section [slot0_idx, slot1_idx, slot2_idx]
      :section_slot_indices,
      # Running state for each slot (panel_idx -> true/false)
      :slot_states,
      # Current sprite canvas for each slot (for animations)
      :slot_canvases,
      # Animation duration for each slot (set when slot starts/restarts)
      :slot_animation_durations,
      # Track which slots are currently animating to prevent multiple animations
      :slot_animating_states,
      :panel_width,
      :display_info,
      :last_win_check_time,
      :blink_state
    ]
  end

  def name(), do: "Slot Machine"

  def compatible?() do
    # Only compatible with 12-panel circular installations like triple_tla
    installation_info = get_installation_info()

    installation_info.panel_count == 12 and Octopus.Installation.arrangement() == :circular and
      installation_info.panel_width >= 8 and installation_info.panel_height >= 8
  end

  def app_init(_) do
    # Configure display for adjacent panels layout
    Octopus.App.configure_display(layout: :adjacent_panels)

    # Subscribe to button events
    Octopus.App.subscribe_to_button_events()

    # Get display information
    display_info = Octopus.App.get_display_info()

    # Load and select sprite groups - need at least 6 sprites per group for slot machine
    available_groups =
      @sprite_groups
      |> Enum.filter(fn {_name, sprites} -> length(sprites) >= 6 end)

    # Select 3 random sprite groups (one per section)
    selected_groups = Enum.take_random(available_groups, 3)

    # Create sprite groups for each section (0, 1, 2)
    section_sprite_groups =
      0..2
      |> Enum.map(fn section_idx ->
        {group_name, sprites} = Enum.at(selected_groups, section_idx)

        # Limit to 6 sprites per section for winnable slot machine
        section_sprites = sprites |> Enum.shuffle() |> Enum.take(6)

        # Each section has 3 slots, all using the SAME 6 sprites but in different random orders
        slot_sprite_lists =
          0..2
          |> Enum.map(fn _slot_idx -> Enum.shuffle(section_sprites) end)

        {section_idx, {group_name, slot_sprite_lists}}
      end)
      |> Enum.into(%{})

    # Initialize current sprite indices for each slot in each section
    section_slot_indices =
      0..2
      |> Enum.map(fn section_idx ->
        {_group_name, slot_sprite_lists} = Map.get(section_sprite_groups, section_idx)

        # Random starting index for each slot in this section
        slot_indices =
          slot_sprite_lists
          |> Enum.map(fn sprite_list -> :rand.uniform(length(sprite_list)) - 1 end)

        {section_idx, slot_indices}
      end)
      |> Enum.into(%{})

    # All slots start running (true = running, false = stopped)
    # all active panels/slots
    slot_states =
      [0, 1, 2, 4, 5, 6, 8, 9, 10]
      |> Enum.map(fn panel_idx -> {panel_idx, true} end)
      |> Enum.into(%{})

    # Generate random animation durations for active slots only (skip gap panels)
    active_slots = [0, 1, 2, 4, 5, 6, 8, 9, 10]

    slot_animation_durations =
      active_slots
      |> Enum.map(fn slot_panel_idx -> {slot_panel_idx, generate_slot_animation_duration()} end)
      |> Enum.into(%{})

    state = %State{
      sprite_groups: @sprite_groups |> Enum.into(%{}),
      section_sprite_groups: section_sprite_groups,
      slot_canvases: %{},
      slot_animation_durations: slot_animation_durations,
      # Track which slots are currently animating
      slot_animating_states: %{},
      section_slot_indices: section_slot_indices,
      slot_states: slot_states,
      panel_width: display_info.panel_width,
      display_info: display_info,
      last_win_check_time: 0,
      blink_state: nil
    }

    # Start rolling timers for all slots (all slots start running)
    # Skip gap panels 3, 7, 11
    active_slots = [0, 1, 2, 4, 5, 6, 8, 9, 10]

    for slot_panel_idx <- active_slots do
      # Start rolling immediately with small random initial delay
      initial_delay = :rand.uniform(200)
      :timer.send_after(initial_delay, {:roll_slot, slot_panel_idx})

      Logger.debug("Slot Machine: Starting slot #{slot_panel_idx} rolling in #{initial_delay}ms")
    end

    render_display(state)

    {:ok, state}
  end

  # Panel and section mapping functions
  defp panel_to_section(panel_idx) do
    cond do
      panel_idx in [0, 1, 2] -> 0
      panel_idx in [4, 5, 6] -> 1
      panel_idx in [8, 9, 10] -> 2
      true -> nil
    end
  end

  defp panel_to_slot_in_section(panel_idx) do
    cond do
      # slot 0, 1, 2 in section 0
      panel_idx in [0, 1, 2] -> panel_idx
      # slot 0, 1, 2 in section 1
      panel_idx in [4, 5, 6] -> panel_idx - 4
      # slot 0, 1, 2 in section 2
      panel_idx in [8, 9, 10] -> panel_idx - 8
      true -> nil
    end
  end

  defp section_to_panels(section) do
    case section do
      # Section 0: panels 1-3 (0-indexed)
      0 -> [0, 1, 2]
      # Section 1: panels 5-7 (0-indexed)
      1 -> [4, 5, 6]
      # Section 2: panels 9-11 (0-indexed)
      2 -> [8, 9, 10]
      _ -> []
    end
  end

  # Button to slot mapping (buttons 1-3, 5-7, 9-11 control corresponding panels)
  defp button_to_slot(button) do
    cond do
      # buttons 1,2,3 -> panels 0,1,2
      button in [1, 2, 3] -> button - 1
      # buttons 5,6,7 -> panels 4,5,6
      button in [5, 6, 7] -> button - 1
      # buttons 9,10,11 -> panels 8,9,10
      button in [9, 10, 11] -> button - 1
      true -> nil
    end
  end

  # Rolling handler for individual slots - only called when slot should start a new animation
  def handle_info({:roll_slot, slot_panel_idx}, state) do
    is_running = Map.get(state.slot_states, slot_panel_idx, false)
    is_animating = Map.get(state.slot_animating_states, slot_panel_idx, false)

    Logger.debug(
      "Slot Machine: Roll slot #{slot_panel_idx} - running: #{is_running}, animating: #{is_animating}"
    )

    if is_running and not is_animating do
      Logger.info("Slot Machine: Starting animation for slot #{slot_panel_idx}")
      # Start animation - next one will be scheduled when this completes
      state = animate_next_sprite_for_slot(state, slot_panel_idx)
      {:noreply, state}
    else
      # Don't schedule anything - either stopped or animation will handle next roll
      {:noreply, state}
    end
  end

  # Blink animation handler
  def handle_info({:blink, count_remaining}, state) when count_remaining > 0 do
    # Toggle blink state and update display
    new_blink_state = if state.blink_state == :on, do: :off, else: :on
    state = %State{state | blink_state: new_blink_state}
    render_display(state)

    # Schedule next blink
    :timer.send_after(@blink_interval, {:blink, count_remaining - 1})
    {:noreply, state}
  end

  def handle_info({:blink, 0}, state) do
    # Blinking finished, restart all slots with new random animation durations

    # Restart rolling for all active slots with new random animation durations
    active_slots = [0, 1, 2, 4, 5, 6, 8, 9, 10]

    new_slot_animation_durations =
      active_slots
      |> Enum.map(fn slot_panel_idx -> {slot_panel_idx, generate_slot_animation_duration()} end)
      |> Enum.into(%{})

    # Restart all slots
    new_slot_states =
      active_slots
      |> Enum.map(fn slot_panel_idx -> {slot_panel_idx, true} end)
      |> Enum.into(%{})

    for slot_panel_idx <- active_slots do
      # Add random initial delay
      initial_delay = :rand.uniform(200)
      :timer.send_after(initial_delay, {:roll_slot, slot_panel_idx})

      Logger.info(
        "Slot Machine: Restarting slot #{slot_panel_idx} rolling in #{initial_delay}ms (new duration: #{Map.get(new_slot_animation_durations, slot_panel_idx)}ms)"
      )
    end

    updated_state = %State{
      state
      | slot_animation_durations: new_slot_animation_durations,
        slot_states: new_slot_states,
        blink_state: nil
    }

    render_display(updated_state)
    {:noreply, updated_state}
  end

  # Animation update handler
  def handle_info({:animate_slot, slot_panel_idx, target_canvas, animation_duration}, state) do
    # Get current canvas for this slot or start from blank
    current_canvas =
      case Map.get(state.slot_canvases, slot_panel_idx) do
        nil ->
          # Start from blank canvas for first animation
          Canvas.new(state.panel_width, state.panel_width)

        existing_canvas ->
          existing_canvas
      end

    # Create rolling transition (top-down like slot machine)
    transition_fun = fn _blank, to_canvas ->
      Transitions.push(current_canvas, to_canvas,
        direction: :bottom,
        steps: 20
      )
    end

    # Use Animator for non-blocking animation
    Animator.animate(
      animation_id: {:slot, slot_panel_idx},
      app_pid: self(),
      canvas: target_canvas,
      position: {0, 0},
      transition_fun: transition_fun,
      duration: animation_duration,
      canvas_size: {state.panel_width, state.panel_width},
      frame_rate: 30
    )

    {:noreply, state}
  end

  def handle_info({:animator_update, animation_id, canvas, frame_status}, state) do
    # Handle canvas updates from the Animator module
    case animation_id do
      {:slot, slot_panel_idx} ->
        # Update the specific slot canvas
        updated_slot_canvases = Map.put(state.slot_canvases, slot_panel_idx, canvas)

        # Check if animation is completed
        updated_state =
          if frame_status == :final do
            # Mark slot as not animating
            new_slot_animating_states =
              Map.put(state.slot_animating_states, slot_panel_idx, false)

            # Immediately schedule next animation if slot is still running
            if Map.get(state.slot_states, slot_panel_idx, false) do
              send(self(), {:roll_slot, slot_panel_idx})
            end

            %State{
              state
              | slot_canvases: updated_slot_canvases,
                slot_animating_states: new_slot_animating_states
            }
          else
            # Animation still in progress, just update canvas
            %State{state | slot_canvases: updated_slot_canvases}
          end

        # Render full display with updated slot
        render_display(updated_state)

        {:noreply, updated_state}

      _ ->
        {:noreply, state}
    end
  end

  def handle_info(msg, state) do
    Logger.warning("Unexpected message in Slot Machine: #{inspect(msg)}")
    {:noreply, state}
  end

  # Button event handler
  def handle_event(%InputEvent{type: :button, action: :press, button: button_id}, state) do
    case button_to_slot(button_id) do
      nil ->
        {:noreply, state}

      slot_panel_idx ->
        # Toggle slot state (stop or start rolling)
        current_state = Map.get(state.slot_states, slot_panel_idx, false)
        new_slot_states = Map.put(state.slot_states, slot_panel_idx, not current_state)

        updated_state =
          if current_state do
            # Slot was running, now stopped
            state
          else
            # Slot was stopped, now starting
            # Generate new random animation duration for this slot
            new_duration = generate_slot_animation_duration()

            new_slot_animation_durations =
              Map.put(state.slot_animation_durations, slot_panel_idx, new_duration)

            # Start rolling with random initial delay
            initial_delay = :rand.uniform(200)
            :timer.send_after(initial_delay, {:roll_slot, slot_panel_idx})

            Logger.debug(
              "Slot Machine: Starting slot #{slot_panel_idx} rolling in #{initial_delay}ms (duration: #{new_duration}ms)"
            )

            %State{state | slot_animation_durations: new_slot_animation_durations}
          end

        final_state = %State{updated_state | slot_states: new_slot_states}

        # Check for win condition for this slot's section
        section = panel_to_section(slot_panel_idx)

        final_state_with_win_check =
          if section != nil do
            check_section_win_condition(final_state, section)
          else
            final_state
          end

        {:noreply, final_state_with_win_check}
    end
  end

  def handle_event(_event, state) do
    {:noreply, state}
  end

  # Animate next sprite for a specific slot
  defp animate_next_sprite_for_slot(state, slot_panel_idx) do
    section = panel_to_section(slot_panel_idx)
    slot_in_section = panel_to_slot_in_section(slot_panel_idx)

    {_group_name, slot_sprite_lists} = Map.get(state.section_sprite_groups, section)
    slot_indices = Map.get(state.section_slot_indices, section)

    # Update this specific slot's sprite index
    sprite_list = Enum.at(slot_sprite_lists, slot_in_section)
    current_index = Enum.at(slot_indices, slot_in_section)
    next_index = rem(current_index + 1, length(sprite_list))

    # Get next sprite and create target canvas
    next_sprite_id = Enum.at(sprite_list, next_index)
    target_canvas = load_sprite(next_sprite_id, state.panel_width)

    # Get slot-specific animation duration (set when slot starts/restarts)
    animation_duration =
      Map.get(state.slot_animation_durations, slot_panel_idx, @default_animation_duration)

    # Mark slot as animating to prevent multiple animations
    new_slot_animating_states = Map.put(state.slot_animating_states, slot_panel_idx, true)

    # Start animation immediately
    send(self(), {:animate_slot, slot_panel_idx, target_canvas, animation_duration})

    # Update state with new index and animating state
    new_slot_indices = List.replace_at(slot_indices, slot_in_section, next_index)
    new_section_slot_indices = Map.put(state.section_slot_indices, section, new_slot_indices)

    %State{
      state
      | section_slot_indices: new_section_slot_indices,
        slot_animating_states: new_slot_animating_states
    }
  end

  # Check for win condition in a specific section
  defp check_section_win_condition(state, section) do
    section_panels = section_to_panels(section)

    # Check if all slots in this section are stopped
    all_stopped =
      Enum.all?(section_panels, fn panel_idx ->
        not Map.get(state.slot_states, panel_idx, false)
      end)

    if all_stopped do
      # Get current sprites for all slots in this section
      {_group_name, slot_sprite_lists} = Map.get(state.section_sprite_groups, section)
      slot_indices = Map.get(state.section_slot_indices, section)

      current_sprites =
        slot_indices
        |> Enum.with_index()
        |> Enum.map(fn {sprite_idx, slot_idx} ->
          sprite_list = Enum.at(slot_sprite_lists, slot_idx)
          Enum.at(sprite_list, sprite_idx)
        end)

      # Check if all sprites in this section are the same
      if Enum.uniq(current_sprites) |> length() == 1 do
        # Start blinking animation
        :timer.send_after(@blink_interval, {:blink, @blink_count * 2})

        %State{state | blink_state: :on}
      else
        state
      end
    else
      state
    end
  end

  defp render_display(state) do
    display_canvas = render_slots_to_canvas(state)
    Octopus.App.update_display(display_canvas)
  end

  defp render_slots_to_canvas(state) do
    display_canvas = Canvas.new(state.display_info.width, state.display_info.height)

    # Render each section
    Enum.reduce(0..2, display_canvas, fn section, canvas ->
      section_panels = section_to_panels(section)
      {_group_name, slot_sprite_lists} = Map.get(state.section_sprite_groups, section)
      slot_indices = Map.get(state.section_slot_indices, section)

      # Render each slot in the section with its own sprite
      Enum.reduce(Enum.with_index(section_panels), canvas, fn {panel_idx, slot_idx_in_section},
                                                              acc_canvas ->
        # Use animated canvas if available, otherwise load current sprite
        sprite_canvas =
          case Map.get(state.slot_canvases, panel_idx) do
            nil ->
              # No animated canvas, load current sprite
              sprite_list = Enum.at(slot_sprite_lists, slot_idx_in_section)
              current_index = Enum.at(slot_indices, slot_idx_in_section)
              sprite_id = Enum.at(sprite_list, current_index)
              load_sprite(sprite_id, state.panel_width)

            animated_canvas ->
              # Use the animated canvas from Animator
              animated_canvas
          end

        # Apply blink effect if winning
        final_sprite_canvas =
          if state.blink_state == :off do
            # Blank for blink off
            Canvas.new(state.panel_width, state.panel_width)
          else
            sprite_canvas
          end

        # Place sprite on this panel
        x_offset = panel_idx * state.panel_width
        Canvas.overlay(acc_canvas, final_sprite_canvas, offset: {x_offset, 0})
      end)
    end)
  end

  defp load_sprite(sprite_index, panel_width) do
    # Load the original 8x8 sprite
    original_sprite = Sprite.load(@sprite_sheet, sprite_index)

    cond do
      panel_width == 8 ->
        # Perfect match, use sprite as-is
        original_sprite

      panel_width > 8 ->
        # Panel is larger than sprite, center the sprite within the panel
        new_canvas = Canvas.new(panel_width, panel_width)
        offset_x = div(panel_width - 8, 2)
        offset_y = div(panel_width - 8, 2)
        Canvas.overlay(new_canvas, original_sprite, offset: {offset_x, offset_y})

      panel_width < 8 ->
        # Panel is smaller than sprite, crop the sprite to fit
        Canvas.cut(original_sprite, {0, 0}, {panel_width - 1, panel_width - 1})
    end
  end
end
