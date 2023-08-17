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

    %State{
      state
      | lemmings:
          state.lemmings
          |> Enum.map(fn lem ->
            lem
            |> Lemming.tick()
            |> Lemming.boundaries([0, 7 * (18 + 8)], [242, 6 * (18 + 8) - 18])
          end),
        t: state.t + 1
    }
  end

  def action_allowed?(action_map, action, now, min_distance) do
    IO.inspect([action_map, action, now, min_distance])

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
      | lemmings: [Lemming.walking_left() | state.lemmings],
        actions: state.actions |> update_action(action, state.t, @default_block_time)
    }

    state
  end

  def add_right(state), do: state

  def handle_info(:tick, %State{} = state) do
    {:noreply, tick(state)}
  end

  def handle_input(%InputEvent{type: :AXIS_X_1, value: 1}, state) do
    state = add_left(state)
    {:noreply, state}
  end

  def handle_input(%InputEvent{type: :AXIS_X_1, value: -1}, state) do
    state = add_right(state)

    {:noreply, state}
  end

  def handle_input(_, state) do
    {:noreply, state}
  end
end
