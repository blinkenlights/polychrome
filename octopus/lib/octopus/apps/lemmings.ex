defmodule Octopus.Apps.Lemmings do
  use Octopus.App, category: :animation
  require Logger

  alias Octopus.{Sprite, Canvas}
  alias Octopus.Protobuf.{AudioFrame, InputEvent}

  defmodule Lemming do
    defstruct frames: nil, anchor: {-4, 0}, anim_step: 0, state: :walk_right, offsets: %{}

    def turn(%Lemming{anchor: {x, y}} = lem) do
      {new_state, xoffset} =
        cond do
          lem.state == :walk_right -> {:walk_left, -2}
          true -> {:walk_right, 2}
        end

      %Lemming{
        lem
        | state: new_state,
          anchor: {x + xoffset, y},
          frames: lem.frames |> Enum.map(&Canvas.flip_horizontal/1),
          offsets: lem.offsets |> Enum.map(fn {i, {x, y}} -> {i, {-x, y}} end) |> Enum.into(%{})
      }
    end

    def walking_right do
      %Lemming{
        anchor: {0, 0},
        frames: Sprite.load(Path.join(["lemmings", "LemmingWalk"])),
        offsets: 0..7 |> Enum.map(fn i -> {i, {1, 0}} end) |> Enum.into(%{})
      }
    end

    def walking_left do
      %Lemming{
        (walking_right()
         |> turn())
        | anchor: {240, 0}
      }
    end

    def stopper(pos) do
      %Lemming{
        anchor: {pos * (18 + 8), 0},
        frames: Sprite.load(Path.join(["lemmings", "LemmingStopper"])),
        state: :stopper
      }
    end

    def tick(%Lemming{} = sprite) do
      {dx, dy} = Map.get(sprite.offsets, sprite.anim_step, {0, 0})
      {x, y} = sprite.anchor

      %Lemming{
        sprite
        | anchor: {x + dx, y + dy},
          anim_step: rem(sprite.anim_step + 1, length(sprite.frames))
      }
    end

    def boundaries(%Lemming{state: :walk_right, anchor: {x, _}} = lem, _, [bound | tail]) do
      cond do
        x == bound - 4 -> turn(lem)
        true -> boundaries(lem, [], tail)
      end
    end

    def boundaries(%Lemming{state: :walk_left, anchor: {x, _}} = lem, [bound | tail], _) do
      cond do
        x == bound - 4 -> turn(lem)
        true -> boundaries(lem, tail, [])
      end
    end

    def boundaries(%Lemming{} = lem, _, _), do: lem

    def sprite(%Lemming{} = lem) do
      lem.frames
      |> Enum.at(lem.anim_step)
    end
  end

  defmodule State do
    defstruct t: 0, lemmings: []
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
    #    |> IO.inspect()
    |> Enum.reduce(Canvas.new(242, 8), fn sprite, canvas ->
      canvas
      |> Canvas.overlay(Lemming.sprite(sprite), offset: sprite.anchor)
    end)
    |> Canvas.to_frame(drop: true)
    |> send_frame()

    state = %State{
      lemmings:
        state.lemmings
        |> Enum.map(fn lem ->
          lem |> Lemming.tick() |> Lemming.boundaries([0, 7 * (18 + 8)], [242, 6 * (18 + 8) - 18])
        end),
      t: state.t + 1
    }
  end

  def add_left(%State{} = state) do
    send_frame(%AudioFrame{uri: "file://lemmings/letsgo.wav", channel: 1})

    state = %State{
      lemmings: [Lemming.walking_right() | state.lemmings]
    }

    state
  end

  def add_right(%State{} = state) do
    send_frame(%AudioFrame{uri: "file://lemmings/letsgo.wav", channel: 10})

    state = %State{
      lemmings: [Lemming.walking_left() | state.lemmings]
    }

    state
  end

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
