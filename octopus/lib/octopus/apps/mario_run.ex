defmodule Octopus.Apps.MarioRun do
  alias Octopus.Events.Event.Input, as: InputEvent
  alias Octopus.Canvas
  alias Octopus.Sprite
  alias Octopus.WebP

  use Octopus.App, category: :animation

  @loops %{
    run: [
      {0, {80, 130}, false},
      {1, {80, 130}, false},
      {2, {80, 130}, false},
      {3, {80, 130}, false},
      {4, {80, 130}, false},
      {5, {80, 130}, false}
    ],
    look1: [
      {6, 800, false},
      {7, 400, false},
      {8, 800, false}
    ],
    look2: [
      {6, 600, false},
      {7, 300, false},
      {8, 300, false},
      {7, 300, false},
      {6, 600, false}
    ],
    look3: [
      {6, 600, false},
      {7, 300, false},
      {8, 600, false},
      {6, 600, true},
      {7, 300, true},
      {8, 600, true}
    ]
  }

  defmodule State do
    defstruct [
      :canvas,
      :time,
      :sprite_sheets,
      :loop,
      :next_loop,
      :character,
      :current_frame,
      :speed,
      :look_speed,
      :char_x,
      :virtual_width,
      :panel_stride,
      :sprite_width,
      :pending_loop,
      :look_timer_ref,
      :look_duration_timer_ref
    ]
  end

  def name, do: "Mario Run"

  def icon, do: WebP.load("mario")

  def config_schema do
    %{
      speed: {"Run Speed", :float, %{default: 1.0, min: 0.1, max: 10.0}},
      look_speed: {"Look Speed", :float, %{default: 0.5, min: 0.1, max: 5.0}}
    }
  end

  def get_config(%State{} = state) do
    %{speed: state.speed, look_speed: state.look_speed}
  end

  def app_init(_) do
    # Configure display using new unified API - gapped_panels_wrapped layout for seamless wrapping
    Octopus.App.configure_display(layout: :gapped_panels_wrapped)
    Octopus.App.subscribe_to_button_events()

    sprite_sheets = %{
      mario: "mario-run",
      luigi: "luigi-run"
    }

    # Get display info instead of VirtualMatrix
    display_info = Octopus.App.get_display_info()
    virtual_width = display_info.width
    virtual_height = display_info.height

    # Calculate panel stride (distance between panel starts) for positioning logic
    panel_width = display_info.panel_width
    panel_gap = display_info.panel_gap
    panel_stride = panel_width + panel_gap

    # Assume sprite width is 8 pixels (standard Mario sprite width)
    sprite_width = 8

    state = %State{
      canvas: Canvas.new(virtual_width, virtual_height),
      time: 0.0,
      sprite_sheets: sprite_sheets,
      character: :luigi,
      current_frame: 0,
      loop: :run,
      next_loop: :run,
      speed: 3,
      look_speed: 0.8,
      char_x: virtual_width - sprite_width - 1,
      virtual_width: virtual_width,
      panel_stride: panel_stride,
      sprite_width: sprite_width,
      pending_loop: nil,
      look_timer_ref: nil,
      look_duration_timer_ref: nil
    }

    # Schedule first random look animation after initialization
    look_timer_ref = schedule_random_look()
    state = %State{state | look_timer_ref: look_timer_ref}

    Process.send_after(self(), :tick, 0)

    {:ok, state}
  end

  # Handle animation frame progression and loop transitions
  defp animate(%State{current_frame: current_frame} = state, loop, _next_loop) do
    loop_length = length(@loops[loop])

    cond do
      # Animation continues within current loop
      current_frame + 1 < loop_length ->
        %State{state | loop: loop, current_frame: current_frame + 1}

      # Animation completes, loop back to beginning (look animations will be ended by timer)
      true ->
        %State{state | loop: loop, current_frame: 0}
    end
  end

  defp schedule_next_frame({min, max}, speed) do
    duration = Enum.random(min..max)
    schedule_next_frame(duration, speed)
  end

  defp schedule_next_frame(duration, speed) do
    Process.send_after(self(), :tick, trunc(duration * (1 / speed)))
  end

  # Schedule a random look animation between 5-10 seconds
  defp schedule_random_look() do
    delay = Enum.random(5_000..10_000)
    Process.send_after(self(), :random_look, delay)
  end

  # Character moves when running
  defp update_position(%State{loop: :run, char_x: char_x}), do: char_x + 1

  # Character stops moving during look animations
  defp update_position(%State{loop: loop, char_x: char_x}) when loop != :run, do: char_x

  # Character moves when no pending look animation
  defp update_position(%State{pending_loop: nil, char_x: char_x}), do: char_x + 1

  # Character stops moving when on panel with pending look animation
  defp update_position(%State{char_x: char_x, panel_stride: panel_stride, pending_loop: _pending})
       when rem(char_x, panel_stride) == 0 do
    char_x
  end

  # Character continues moving toward panel when pending look animation
  defp update_position(%State{char_x: char_x, pending_loop: _pending}), do: char_x + 1

  # Activate pending loop when character reaches a panel
  defp handle_loop_transition(
         %State{pending_loop: pending_loop, panel_stride: panel_stride} = _state,
         char_x
       )
       when pending_loop != nil and rem(char_x, panel_stride) == 0 do
    # Schedule return to run state after 2 seconds
    look_duration_timer_ref = Process.send_after(self(), :end_look_animation, 2000)
    {pending_loop, pending_loop, nil, look_duration_timer_ref}
  end

  # Keep current state when pending loop exists but not on panel
  defp handle_loop_transition(%State{pending_loop: pending_loop} = state, _char_x)
       when pending_loop != nil do
    {state.loop, state.next_loop, pending_loop, state.look_duration_timer_ref}
  end

  # No pending loop, maintain current state
  defp handle_loop_transition(state, _char_x) do
    {state.loop, state.next_loop, state.pending_loop, state.look_duration_timer_ref}
  end

  # Switch Mario to Luigi when crossing boundary
  defp handle_character_switch(
         %State{char_x: old_x, character: :mario, sprite_width: sprite_width},
         new_x,
         virtual_width
       )
       when old_x < virtual_width - sprite_width and new_x >= virtual_width - sprite_width do
    :luigi
  end

  # Switch Luigi to Mario when crossing boundary
  defp handle_character_switch(
         %State{char_x: old_x, character: :luigi, sprite_width: sprite_width},
         new_x,
         virtual_width
       )
       when old_x < virtual_width - sprite_width and new_x >= virtual_width - sprite_width do
    :mario
  end

  # No character switch needed
  defp handle_character_switch(%State{character: character}, _new_x, _virtual_width) do
    character
  end

  def handle_info(:random_look, %State{loop: :run, pending_loop: nil} = state) do
    look_animation = Enum.random([:look1, :look2, :look3])
    {:noreply, %State{state | pending_loop: look_animation, look_timer_ref: nil}}
  end

  def handle_info(:random_look, %State{} = state) do
    look_timer_ref = schedule_random_look()
    {:noreply, %State{state | look_timer_ref: look_timer_ref}}
  end

  def handle_info(:end_look_animation, %State{} = state) do
    look_timer_ref = schedule_random_look()

    {:noreply,
     %State{
       state
       | loop: :run,
         next_loop: :run,
         look_timer_ref: look_timer_ref,
         look_duration_timer_ref: nil
     }}
  end

  def handle_info(:tick, %State{} = state) do
    {sprite_index, duration, flip} = Enum.at(@loops[state.loop], state.current_frame)
    sprite_sheet = state.sprite_sheets[state.character]
    sprite = Sprite.load(sprite_sheet, sprite_index)

    # Update character position
    new_char_x = update_position(state)
    char_x = rem(new_char_x + state.virtual_width, state.virtual_width)

    # Handle loop transitions
    {loop, next_loop, pending_loop, look_duration_timer_ref} =
      handle_loop_transition(state, char_x)

    # Handle character switching
    character = handle_character_switch(state, new_char_x, state.virtual_width)

    # Render character
    canvas =
      render_character(
        state.canvas,
        sprite,
        char_x,
        state.virtual_width,
        state.sprite_width,
        flip
      )

    # Use new unified display API
    Octopus.App.update_display(canvas)

    # Animate and update state
    new_state = animate(state, loop, next_loop)
    current_speed = if loop == :run, do: state.speed, else: state.look_speed
    schedule_next_frame(duration, current_speed)

    {:noreply,
     %State{
       new_state
       | canvas: canvas,
         char_x: char_x,
         character: character,
         pending_loop: pending_loop,
         look_duration_timer_ref: look_duration_timer_ref
     }}
  end

  defp render_character(canvas, sprite, char_x, virtual_width, sprite_width, flip) do
    canvas
    |> Canvas.clear()
    |> Canvas.overlay(sprite, offset: {char_x, 0})
    |> then(fn canvas ->
      if char_x >= virtual_width - sprite_width do
        wrapped_x = char_x - virtual_width
        Canvas.overlay(canvas, sprite, offset: {wrapped_x, 0})
      else
        canvas
      end
    end)
    |> then(&if(flip, do: Canvas.flip(&1, :horizontal), else: &1))
  end

  def handle_config(%{speed: speed, look_speed: look_speed}, %State{} = state) do
    {:noreply, %State{state | speed: speed, look_speed: look_speed}}
  end

  def handle_event(%InputEvent{type: :button, action: :press, button: 1}, %State{} = state) do
    # Cancel any pending look animation and return to run immediately
    if state.look_timer_ref do
      Process.cancel_timer(state.look_timer_ref)
    end

    if state.look_duration_timer_ref do
      Process.cancel_timer(state.look_duration_timer_ref)
    end

    new_timer_ref = schedule_random_look()

    {:noreply,
     %State{
       state
       | loop: :run,
         next_loop: :run,
         pending_loop: nil,
         look_timer_ref: new_timer_ref,
         look_duration_timer_ref: nil
     }}
  end

  def handle_event(
        %InputEvent{type: :button, action: :press, button: 10},
        %State{character: :mario} = state
      ) do
    {:noreply, %State{state | character: :luigi}}
  end

  def handle_event(
        %InputEvent{type: :button, action: :press, button: 10},
        %State{character: :luigi} = state
      ) do
    {:noreply, %State{state | character: :mario}}
  end

  def handle_event(_event, %State{} = state) do
    {:noreply, state}
  end
end
