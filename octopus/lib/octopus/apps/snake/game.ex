defmodule Octopus.Apps.Snake.Game do

  defmodule Worm do
    @base_speed 40
    defstruct [:parts,:rem_t]

    def new() do
      %Worm { parts: [{{3,7},:u}, {{2,7}, :r}, {{1,7}, :r}], rem_t: @base_speed }
    end

    defp move(parts, dir), do: move([], parts, dir)

    defp move(acc,[],_), do: Enum.reverse(acc)
    defp move(acc,[{{x,y}, pdir} | tail], dir) do
      newpos = case pdir do
        :u -> {x,y-1}
        :d -> {x,y+1}
        :l -> {x-1,y}
        :r -> {x+1,y}
      end

      move([{newpos, dir} | acc], tail, pdir)
    end

    def tick(worm, [dir | _]), do: tick(worm, dir)
    def tick(%Worm{ parts: [{_,dir} | _]} = worm, []), do: tick(worm, dir)
    def tick(%Worm{ rem_t: 0} = worm, dir) do
      %Worm{
        parts: move(worm.parts, dir),
        rem_t: @base_speed
      } |> IO.inspect()

    end
    def tick(%Worm{parts: [{pos,_} | parttail], rem_t: rem_t} = worm, dir), do: %Worm{ worm | parts: [{pos, dir} | parttail], rem_t: rem_t-1}

  end

  defstruct [:worm, :food]
  alias Octopus.Canvas
  alias Octopus.Apps.Snake
  alias Snake.JoyState
  alias Snake.Game

  def new() do
    %Game{
      worm: Worm.new(), food: {2,2}
    }
  end

  def new_food(%Worm{} = _worm) do
    {:rand.uniform(8)-1,:rand.uniform(8)-1}
  end

  def tick(%Game{ food: food} = game, joy) do

    new_worm = game.worm |> Worm.tick(JoyState.direction(joy))

    _game = case hd(new_worm.parts) do
    {^food, _} ->
      wormy = %Worm{ new_worm | parts: [hd(new_worm.parts) | game.worm.parts] }
      %Game{
        game |
        worm: wormy,
        food: new_food(wormy)
      }
    _ -> %Game{
      game |
      worm: new_worm
    }
  end
  end

  def render_frame(%Game{} = game) do
    gamecanvas =
      Canvas.new(8,8)
      |> Canvas.put_pixel(game.food, [0xff,0xff,0x00])

    gamecanvas =
    game.worm.parts
    |> Enum.reduce(gamecanvas, fn {pos, _dir}, acc -> acc |> Canvas.put_pixel(pos, [0x10,0xff,0x10]) end)

    Canvas.new(60,8) |> Canvas.overlay(gamecanvas, offset: {8*4,0}) |> Canvas.to_frame()
  end
end
