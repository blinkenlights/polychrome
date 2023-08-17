alias Octopus.{Sprite, Util, Canvas}

defmodule Lemming do
  defstruct frames: nil,
            anchor: {-4, 0},
            anim_step: 0,
            state: :walk_right,
            offsets: %{},
            self_destruct: 999_999_999

  def play_sample(%Lemming{} = lem, name) do
    channel = current_window(lem)
    Octopus.App.play_sample("lemmings/#{name}.wav", channel)
    lem
  end

  def current_window(%Lemming{anchor: {x, _}}) do
    (div(x, 18 + 8) + 1) |> Util.clamp(1, 10)
  end

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

  def explode(%Lemming{} = lem) do
    %Lemming{
      lem
      | state: :ohno,
        frames: Sprite.load(Path.join(["lemmings", "LemmingOhNo"])),
        anim_step: 0,
        offsets: %{}
    }
    |> Lemming.play_sample("ohno")
  end

  def explode_really(%Lemming{} = lem) do
    %Lemming{
      lem
      | state: :explode,
        frames: Sprite.load(Path.join(["lemmings", "LemmingExplode"])),
        anim_step: 0,
        offsets: %{}
    }
    |> Lemming.play_sample("thud")
  end

  def splat(%Lemming{} = lem) do
    %Lemming{
      anchor: lem.anchor,
      state: :splat,
      frames: Sprite.load(Path.join(["lemmings", "LemmingSplat"])),
      anim_step: 0
    }
    |> Lemming.play_sample("splat")
  end

  def walking_right do
    %Lemming{
      anchor: {-4, 0},
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

  def faller(pos) do
    new_lem = %Lemming{
      state: :fall,
      anchor: {pos * (18 + 8), -8},
      frames: Sprite.load(Path.join(["lemmings", "LemmingFall"]))
    }

    new_lem =
      if :rand.uniform(2) == 1 do
        %Lemming{new_lem | frames: new_lem.frames |> Enum.map(&Canvas.flip_horizontal/1)}
      else
        new_lem
      end

    %Lemming{
      new_lem
      | offsets:
          0..(length(new_lem.frames) - 1) |> Enum.map(fn i -> {i, {0, 1}} end) |> Enum.into(%{})
    }
  end

  def button_lemming(number) do
    faller(number)
  end

  def tick(%Lemming{state: :ohno, anim_step: 7} = sprite) do
    Lemming.explode_really(sprite)
  end

  def tick(%Lemming{state: :fall, anchor: {_, 0}} = sprite) do
    case :rand.uniform(5) do
      5 ->
        Lemming.splat(sprite)

      4 ->
        %Lemming{
          Lemming.walking_right()
          | anchor: sprite.anchor
        }

      3 ->
        %Lemming{
          Lemming.walking_left()
          | anchor: sprite.anchor
        }

      2 ->
        sprite |> Lemming.play_sample("thunk")
        Lemming.stopper(Lemming.current_window(sprite) - 1)

      1 ->
        inner_tick(sprite) |> Lemming.play_sample("ohno")
    end
  end

  def tick(%Lemming{} = sprite) do
    inner_tick(sprite)
  end

  defp inner_tick(%Lemming{anchor: {0, 20}}), do: nil

  defp inner_tick(%Lemming{} = sprite) do
    {dx, dy} = Map.get(sprite.offsets, sprite.anim_step, {0, 0})
    {x, y} = sprite.anchor

    ticked = %Lemming{
      sprite
      | anchor: {x + dx, y + dy},
        anim_step: rem(sprite.anim_step + 1, length(sprite.frames))
    }

    if ticked.anim_step == 0 && ticked.state in [:splat, :explode] do
      nil
    else
      ticked
    end
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
