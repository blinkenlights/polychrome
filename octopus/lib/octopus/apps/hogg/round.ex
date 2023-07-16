defmodule Octopus.Apps.Hogg.Round do
  defstruct [:t, :players, :canvas]
  alias Octopus.Apps.Hogg
  alias Hogg.Round
  alias Hogg.JoyState
  alias Hogg.Util
  alias Octopus.ColorPalette
  alias Octopus.Canvas

  defmodule Player do
    defstruct pos: {39, 1},
              vel: {0, 0},
              base_color: [128, 255, 128],
              weapon_color: [128, 128, 128],
              ducks: false,
              stabs: false,
              facing: 1,
              can_jump: false,
              last_jump: -100

    def new(0) do
      %Player{pos: {8 * 3 + 4, 1}}
    end

    def new(1) do
      %Player{pos: {8 * 6 + 3, 1}, base_color: [255, 128, 128], facing: -1}
    end

    def weapon_pixels(%Player{stabs: false}), do: []

    def weapon_pixels(%Player{pos: {x, y}, facing: facing, ducks: ducks}) do
      weapon_y = if(ducks, do: y, else: y - 1)
      [{facing + x, weapon_y}, {facing * 2 + x, weapon_y}]
    end
  end

  def new() do
    %Round{t: 0, canvas: Canvas.new(80, 8), players: [Player.new(0), Player.new(1)]}
  end

  @horz_acc 0.01
  @horz_max 0.20
  @jump -0.25
  @gravity 0.007

  defp apply_input(%Round{t: t, players: [p1, p2]} = round, [joy1, joy2]) do
    players =
      [{p1, joy1}, {p2, joy2}]
      |> Enum.map(fn {%Player{pos: {x, y}, vel: {dx, dy}} = p, %JoyState{} = joy} ->
        will_jump = p.can_jump and JoyState.button?(joy, :u)

        %Player{
          p
          | vel: {
              cond do
                JoyState.button?(joy, :l) -> dx - @horz_acc
                JoyState.button?(joy, :r) -> dx + @horz_acc
                true -> dx * 0.5
              end
              |> Util.clamp(@horz_max),
              cond do
                will_jump ->
                  @jump

                true ->
                  dy
              end
            },
            ducks: joy |> JoyState.button?(:d),
            stabs: joy |> JoyState.button?(:a),
            last_jump: t
        }
      end)

    %Round{round | players: players}
  end

  defp apply_physics(%Round{players: players} = round) do
    # apply vel
    players =
      players
      |> Enum.map(fn %Player{vel: {dx, dy}} = p ->
        %Player{p | vel: {dx, dy + @gravity}}
      end)

    %Round{round | players: players}
  end

  defp resolve_player_collision([%Player{} = p1, %Player{} = p2]) do
    pre_x_players =
      [p1, p2]
      |> Enum.map(fn %Player{pos: {x, y}, vel: {dx, _dy}} = p ->
        %Player{p | pos: {x - dx, y}}
      end)

    [pxp1, pxp2] = pre_x_players

    {{p1_x, p1_y}, {p2_x, p2_y}, {pxp1_x, _pxp1_y}, {pxp2_x, _pxp2_y}} =
      {p1.pos, p2.pos, pxp1.pos, pxp2.pos}

    crossed_paths =
      case {floor(p1_x) - floor(p2_x), floor(pxp1_x) - floor(pxp2_x)} do
        {x, pre} when x < 0 and pre > 0 -> true
        {x, pre} when x > 0 and pre < 0 -> true
        {0, _} -> true
        {_, 0} -> true
        _ -> false
      end

    cond do
      # todo check height too
      crossed_paths and abs(p1_y - p2_y) < 2.0 ->
        [
          %Player{pxp1 | pos: {pxp1_x + elem(p2.vel, 0), p1_y}},
          %Player{pxp2 | pos: {pxp2_x + elem(p1.vel, 0), p2_y}}
        ]

      true ->
        [p1, p2]
    end
  end

  defp collsion_detection(%Round{players: players, t: t} = round) do
    new_players =
      players
      |> resolve_player_collision()
      |> Enum.map(fn %Player{pos: {x, y}, vel: {dx, dy}} = p ->
        #         {prevx, prevy} = {x - dx, y - dy}
        # Environment
        clampx_max = round.canvas.width - 1
        clampx_min = 0

        {new_x, new_dx} =
          cond do
            round(x) >= clampx_max and dx > 0 -> {clampx_max, 0}
            round(x) <= clampx_min and dx < 0 -> {clampx_min, 0}
            true -> {x, dx}
          end

        clampy_max = 7
        clampy_min = 0

        {new_y, new_dy} =
          cond do
            round(y) >= clampy_max and dy > 0 -> {clampy_max, 0}
            round(y) <= clampy_min and dy < 0 -> {clampy_min, 0}
            true -> {y, dy}
          end

        %Player{
          p
          | pos: {new_x, new_y},
            vel: {new_dx, new_dy},
            can_jump: new_dy == 0 and dy > 0 and p.last_jump + 60 > t,
            facing:
              cond do
                new_dx > 0 -> 1
                new_dx < 0 -> -1
                true -> p.facing
              end
        }
      end)

    %Round{round | players: new_players}
  end

  defp apply_movement(%Round{players: players} = round) do
    players =
      players
      |> Enum.map(fn %Player{pos: {x, y}, vel: {dx, dy}} = p ->
        %Player{p | pos: {x + dx, y + dy}}
      end)

    %Round{round | players: players}
  end

  def tick(%Round{t: t} = round, joylist) do
    round
    |> apply_physics()
    |> apply_input(joylist)
    |> apply_movement()
    |> collsion_detection()
    |> Map.replace(:t, t + 1)
  end

  def render_frame(%Round{t: t} = round) do
    width = round.canvas.width

    canvas =
      round.canvas
      |> Canvas.put_pixel({rem(Integer.floor_div(t, 10), width), 0}, [123, 255, 255])

    #    state.players |> IO.inspect()

    round.players
    |> Enum.reduce(canvas, fn %Player{pos: {x, y}} = player, canvas ->
      {x, y} = {floor(x), floor(y)}

      canvas
      |> Canvas.put_pixel({x, y}, player.base_color)
      |> (fn
            c, true -> c
            c, false -> c |> Canvas.put_pixel({x, y - 1}, player.base_color)
          end).(player.ducks)
      |> (fn
            c, false ->
              c

            c, true ->
              player
              |> Player.weapon_pixels()
              |> Enum.reduce(c, fn {x, y}, c ->
                Canvas.put_pixel(c, {floor(x), floor(y)}, player.weapon_color)
              end)
          end).(player.stabs)
    end)
    |> Canvas.to_frame()
  end
end
