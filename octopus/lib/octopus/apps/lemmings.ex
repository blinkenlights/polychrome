defmodule Octopus.Apps.Lemmings do
  use Octopus.App, category: :animation

  alias Octopus.{Sprite, Canvas}
  alias Octopus.Events.Event.Input, as: InputEvent
  alias Lemming

  @default_block_time 10

  defmodule State do
    defstruct t: 0, lemmings: [], actions: %{}, button_map: %{}
  end

  def name(), do: "Lemmings"

  def icon(), do: Sprite.load("lemmings/LemmingWalk", 3)

  def compatible?() do
    Octopus.App.get_installation_info().num_panels >= 3
  end

  def app_init(_args) do
    # Configure display with gapped panels layout (original VirtualMatrix default)
    Octopus.App.configure_display(layout: :gapped_panels)
    Octopus.App.subscribe_to_button_events()
    display_info = Octopus.App.get_display_info()

    button_map =
      0..(display_info.num_panels - 1)
      |> Enum.map(fn i -> {"BUTTON_#{i + 1}" |> String.to_atom(), i} end)
      |> Enum.into(%{})

    state = %State{
      lemmings: [
        Lemming.walking_left(display_info),
        Lemming.walking_right(display_info),
        Lemming.stopper(display_info, :rand.uniform(display_info.num_panels - 2))
      ],
      button_map: button_map
    }

    :timer.send_interval(100, :tick)
    {:ok, state}
  end

  defp tick(state) do
    state
    |> tick_reaction()
    |> tick_postprocess()
  end

  defp tick_reaction(%State{t: t} = state) when t in [1600, 3200] do
    display_info = Octopus.App.get_display_info()

    %State{
      state
      | lemmings: [
          Lemming.walking_left(display_info),
          Lemming.walking_right(display_info) | state.lemmings
        ]
    }
  end

  defp tick_reaction(%State{t: t, lemmings: lems} = state)
       when rem(t, 80) == 70 and length(lems) < 6 do
    display_info = Octopus.App.get_display_info()

    {:noreply, new_state} =
      handle_number_button_press(
        state,
        :rand.uniform(display_info.num_panels) - 1
      )

    new_state
  end

  defp tick_reaction(%State{t: t, lemmings: lems} = state)
       when rem(t, 80) == 70 and length(lems) > 8 do
    %State{state | lemmings: explode_first(state.lemmings)}
  end

  defp tick_reaction(state), do: state

  defp tick_postprocess(%State{} = state) do
    display_info = Octopus.App.get_display_info()

    # Render and send the current frame
    render_frame(state.lemmings, display_info)

    # Calculate boundaries from stopper lemmings
    boundaries = calculate_boundaries(state.lemmings, display_info)

    # Update all lemmings and advance time
    %State{
      state
      | lemmings: update_lemmings(state.lemmings, display_info, boundaries),
        t: state.t + 1
    }
  end

  defp render_frame(lemmings, display_info) do
    lemmings
    |> Enum.reduce(Canvas.new(display_info.width, display_info.height), fn sprite, canvas ->
      Canvas.overlay(canvas, Lemming.sprite(sprite), offset: sprite.anchor)
    end)
    |> (&Octopus.App.update_display(&1)).()
  end

  defp calculate_boundaries(lemmings, display_info) do
    lemmings
    |> Enum.reduce({[0], [display_info.width]}, fn
      %Lemming{state: :stopper, anchor: {stopper_x, _}} = _lem, {left_bounds, right_bounds} ->
        # Right-walkers should turn before hitting the left edge of the blocker
        # Left-walkers should turn before hitting the right edge of the blocker
        # Assuming stopper sprite is 8 pixels wide (standard lemming width)
        stopper_width = 8
        left_edge = stopper_x
        right_edge = stopper_x + stopper_width - 1
        {[right_edge | left_bounds], [left_edge | right_bounds]}

      _, boundaries ->
        boundaries
    end)
  end

  defp update_lemmings(lemmings, display_info, boundaries) do
    {left_bounds, right_bounds} = boundaries

    lemmings
    |> Enum.map(&Lemming.tick(&1, display_info))
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&Lemming.boundaries(&1, left_bounds, right_bounds))
  end

  def action_allowed?(action_map, action, now, min_distance) do
    #    IO.inspect([action_map, action, now, min_distance])

    case Map.get(action_map, action) do
      nil -> true
      t when t <= now - min_distance -> true
      _ -> false
    end
  end

  def update_action(action_map, action, now, min_distance) do
    if (case Map.get(action_map, action) do
          nil -> true
          t when t <= now - min_distance -> true
          _ -> false
        end) do
      action_map |> Map.put(action, now)
    else
      action_map
    end
  end

  defp add_lemming(%State{} = state, direction_fun) do
    action = __ENV__.function |> elem(0)
    display_info = Octopus.App.get_display_info()
    new_lem = direction_fun.(display_info)

    if action_allowed?(state.actions, action, state.t, @default_block_time) do
      new_lem |> Lemming.play_sample("letsgo", display_info)
    end

    %State{
      state
      | lemmings:
          if action_allowed?(state.actions, action, state.t, 5) do
            [new_lem | state.lemmings]
          else
            state.lemmings
          end,
        actions: state.actions |> update_action(action, state.t, 5)
    }
  end

  def add_left(%State{} = state), do: add_lemming(state, &Lemming.walking_right/1)

  def add_right(%State{} = state), do: add_lemming(state, &Lemming.walking_left/1)

  def explode_first([%Lemming{state: state} = lem | tail], acc)
      when state in [:stopper, :walk_left, :walk_right] do
    display_info = Octopus.App.get_display_info()
    ([Lemming.explode(lem, display_info) | tail] ++ acc) |> Enum.reverse()
  end

  def explode_first([lem | tail], acc), do: explode_first(tail, [lem | acc])
  def explode_first([], acc), do: acc
  def explode_first(lems), do: explode_first(lems, [])

  def handle_info(:tick, %State{} = state) do
    {:noreply, tick(state)}
  end

  def handle_event(%InputEvent{type: :button, action: :press, button: button}, %State{} = state) do
    # Convert to 0-based indexing for button_map
    button_index = button - 1
    handle_number_button_press(state, button_index)
  end

  def handle_event(
        %InputEvent{type: :joystick, joystick: _joystick, direction: :right},
        %State{} = state
      ) do
    # Right direction adds left-walking lemming
    state = add_left(state)
    {:noreply, state}
  end

  def handle_event(
        %InputEvent{type: :joystick, joystick: _joystick, direction: :left},
        %State{} = state
      ) do
    # Left direction adds right-walking lemming
    state = add_right(state)
    {:noreply, state}
  end

  def handle_event(
        %InputEvent{type: :joystick, joystick: _joystick, direction: :down},
        %State{} = state
      ) do
    # Down direction explodes a lemming
    handle_kill(state)
  end

  def handle_event(_, %State{} = state) do
    {:noreply, state}
  end

  def handle_kill(%State{lemmings: lems} = state) do
    action = :explode_random
    block_time = 5

    if action_allowed?(state.actions, action, state.t, block_time) do
      {:noreply,
       %State{
         state
         | lemmings: explode_first(lems),
           actions: state.actions |> update_action(action, state.t, block_time)
       }}
    else
      {:noreply, state}
    end
  end

  def handle_number_button_press(%State{} = state, number) do
    action = "Button_#{number + 1}" |> String.to_atom()
    block_time = 12
    display_info = Octopus.App.get_display_info()

    {lems, existing_stopper} =
      Enum.reduce(state.lemmings, {[], nil}, fn
        %Lemming{state: :stopper} = lem, {list, nil} ->
          if Lemming.current_panel(lem, display_info) == number do
            {list, lem}
          else
            {[lem | list], nil}
          end

        lem, {list, es} ->
          {[lem | list], es}
      end)

    if action_allowed?(state.actions, action, state.t, block_time) do
      new_lems =
        if existing_stopper do
          [existing_stopper |> Lemming.explode(display_info) | lems]
        else
          new_lem =
            Lemming.button_lemming(display_info, number)
            |> Lemming.play_sample("yippee", display_info)

          [new_lem | state.lemmings]
        end

      {:noreply,
       %State{
         state
         | lemmings: new_lems,
           actions: state.actions |> update_action(action, state.t, block_time)
       }}
    else
      {:noreply, state}
    end
  end
end
