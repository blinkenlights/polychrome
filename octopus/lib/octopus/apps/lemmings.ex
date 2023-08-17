defmodule Octopus.Apps.Lemmings do
  use Octopus.App, category: :animation
  require Logger

  alias Octopus.{Sprite, Canvas, Util}
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
        Lemming.stopper(6)
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
          state
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
      | lemmings: [new_lem | state.lemmings],
        actions: state.actions |> update_action(action, state.t, @default_block_time)
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
      | lemmings: [new_lem | state.lemmings],
        actions: state.actions |> update_action(action, state.t, @default_block_time)
    }

    state
  end

  def add_right(state), do: state

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

  def handle_input(
        %InputEvent{type: :AXIS_Y_1, value: 1},
        %State{lemmings: [%Lemming{state: lemstate} = lem | tail]} = state
      )
      when lemstate in [:stopper, :walk_right, :walk_left] do
    state = %State{
      state
      | lemmings: [Lemming.explode(lem) | tail |> Enum.reverse()] |> Enum.reverse()
    }

    {:noreply, state}
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

  def handle_number_button_press(%State{} = state, number) do
    action = "Button_#{number + 1}" |> String.to_atom()
    block_time = 5

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
            Lemming.button_lemming(number) |> Lemming.play_sample("yippee") |> IO.inspect()

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
