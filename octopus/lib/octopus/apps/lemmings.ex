defmodule Octopus.Apps.Lemmings do
  use Octopus.App, category: :animation
  require Logger

  alias Octopus.{Sprite, Canvas}
  alias Octopus.Protobuf.InputEvent
  alias Lemming

  @default_block_time 10

  defmodule State do
    defstruct t: 0, lemmings: [], actions: %{}
  end

  def name(), do: "Lemmings"

  def icon(), do: Sprite.load("lemmings/LemmingWalk", 3)

  def init(_args) do
    state = %State{
      lemmings: [
        Lemming.walking_left(),
        Lemming.walking_right(),
        Lemming.stopper(:rand.uniform(5) + 3)
      ]
    }

    :timer.send_interval(100, :tick)
    {:ok, state}
  end

  defp tick(%State{} = state) do
    state =
      case state.t do
        t when t in [1600, 3200] ->
          %State{
            state
            | lemmings: [Lemming.walking_left(), Lemming.walking_right() | state.lemmings]
          }

        _ ->
          if rem(state.t, 80) == 70 do
            if length(state.lemmings) < 6 do
              {:noreply, state} = handle_number_button_press(state, :rand.uniform(10) - 1)
              state
            else
              if length(state.lemmings) > 8 do
                %State{state | lemmings: explode_first(state.lemmings)}
              else
                state
              end
            end
          else
            state
          end
      end

    state.lemmings
    |> Enum.reduce(Canvas.new(242, 8), fn sprite, canvas ->
      canvas
      |> Canvas.overlay(Lemming.sprite(sprite), offset: sprite.anchor)
    end)
    |> Canvas.to_frame(drop: true)
    |> send_frame()

    boundaries =
      state.lemmings
      |> Enum.reduce(
        {[0], [242]},
        fn
          %Lemming{state: :stopper} = lem, {l, r} ->
            window = Lemming.current_window(lem)
            {[window * (18 + 8) | l], [(window - 1) * (18 + 8) - 18 | r]}

          _, acc ->
            acc
        end
      )

    %State{
      state
      | lemmings:
          state.lemmings
          |> Enum.map(fn lem ->
            lem
            |> Lemming.tick()
          end)
          |> Enum.reject(&is_nil/1)
          |> Enum.map(fn lem ->
            lem
            |> Lemming.boundaries(boundaries |> elem(0), boundaries |> elem(1))
          end),
        t: state.t + 1
    }
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

  def add_left(%State{} = state) do
    action = __ENV__.function |> elem(0)
    new_lem = Lemming.walking_right()

    if action_allowed?(state.actions, action, state.t, @default_block_time) do
      new_lem |> Lemming.play_sample("letsgo")
    end

    state = %State{
      state
      | lemmings:
          if action_allowed?(state.actions, action, state.t, 5) do
            [new_lem | state.lemmings]
          else
            state.lemmings
          end,
        actions: state.actions |> update_action(action, state.t, 5)
    }

    state
  end

  def add_left(state), do: state

  def add_right(%State{} = state) do
    action = __ENV__.function |> elem(0)
    new_lem = Lemming.walking_left()

    if action_allowed?(state.actions, action, state.t, @default_block_time) do
      new_lem |> Lemming.play_sample("letsgo")
    end

    state = %State{
      state
      | lemmings:
          if action_allowed?(state.actions, action, state.t, 5) do
            [new_lem | state.lemmings]
          else
            state.lemmings
          end,
        actions: state.actions |> update_action(action, state.t, 5)
    }

    state
  end

  def add_right(state), do: state

  def explode_first(lems) do
    explode_first(lems, [])
  end

  def explode_first([%Lemming{state: state} = lem | tail], acc)
      when state in [:stopper, :walk_left, :walk_right] do
    ([Lemming.explode(lem) | tail] ++ acc) |> Enum.reverse()
  end

  def explode_first([lem | tail], acc), do: explode_first(tail, [lem | acc])
  def explode_first([], acc), do: acc

  def handle_info(:tick, %State{} = state) do
    {:noreply, tick(state)}
  end

  @button_map 1..10
              |> Enum.map(fn i -> {"BUTTON_#{i}" |> String.to_atom(), i - 1} end)
              |> Enum.into(%{})

  def handle_input(%InputEvent{type: :AXIS_X_1, value: 1}, state) do
    state = add_left(state)
    {:noreply, state}
  end

  def handle_input(%InputEvent{type: :AXIS_X_1, value: -1}, state) do
    state = add_right(state)
    {:noreply, state}
  end

  def handle_input(%InputEvent{type: :AXIS_X_2, value: -1}, state) do
    state = add_right(state)
    {:noreply, state}
  end

  def handle_input(%InputEvent{type: :AXIS_X_2, value: 1}, state) do
    state = add_left(state)
    {:noreply, state}
  end

  def handle_input(
        %InputEvent{type: :AXIS_Y_1, value: 1},
        %State{} = state
      ) do
    handle_kill(state)
  end

  def handle_input(
        %InputEvent{type: :AXIS_Y_2, value: 1},
        %State{} = state
      ) do
    handle_kill(state)
  end

  def handle_input(%InputEvent{type: type, value: 1}, state) do
    case @button_map[type] do
      nil -> {:noreply, state}
      number -> handle_number_button_press(state, number)
    end
  end

  def handle_input(_, state) do
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

    {lems, existing_stopper} =
      Enum.reduce(state.lemmings, {[], nil}, fn
        %Lemming{state: :stopper} = lem, {list, nil} ->
          if Lemming.current_window(lem) == number + 1 do
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
          [existing_stopper |> Lemming.explode() | lems]
        else
          new_lem =
            Lemming.button_lemming(number) |> Lemming.play_sample("yippee")

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
