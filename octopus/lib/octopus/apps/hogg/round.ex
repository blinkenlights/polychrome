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

    def new(0, xpos) do
      %Player{pos: {xpos, 0}}
    end

    def new(1, xpos) do
      %Player{pos: {xpos, 0}, base_color: [255, 128, 128], facing: -1}
    end

    def new_pair_at_x_pos(xpos) do
      [new(0, xpos - 11), new(1, xpos + 12)]
    end

    def weapon_pixels(%Player{stabs: false}), do: []

    def weapon_pixels(%Player{pos: {x, y}, facing: facing, ducks: ducks}) do
      weapon_y = if(ducks, do: y, else: y - 1)
      [{facing + x, weapon_y}, {facing * 2 + x, weapon_y}]
    end

    def player_pixels(%Player{ducks: false} = p) do
      [{x, y}] = player_pixels(%Player{p | ducks: true})
      [{x, y}, {x, y - 1}]
    end

    def player_pixels(%Player{pos: {x, y}, ducks: true}), do: [{x, y}]

    def was_stabbed(%Player{}, %Player{stabs: false}), do: false

    def was_stabbed(%Player{} = p, %Player{stabs: true} = op) do
      pp = player_pixels(p) |> Enum.map(&to_pix/1)

      weapon_pixels(op)
      |> Enum.map(&to_pix/1)
      |> Enum.any?(fn pix -> pix in pp end)
    end

    def to_pix({x, y}), do: {floor(x), floor(y)}
  end

  def new() do
    %Round{t: 0, canvas: Canvas.new(80, 8), players: Player.new_pair_at_x_pos(39)}
  end

  @horz_acc 0.01
  @horz_max 0.20
  @jump -0.25
  @gravity 0.007

  defp apply_input(%Round{t: t, players: [p1, p2]} = round, [joy1, joy2]) do
    players =
      [{p1, joy1}, {p2, joy2}]
      |> Enum.map(fn {%Player{vel: {dx, dy}} = p, %JoyState{} = joy} ->
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

  @death_distance 16

  defp game_events(
         %Round{
           players: [%Player{pos: {p1x, _}} = p1, %Player{pos: {p2x, _}} = p2] = _players,
           t: t
         } = round
       ) do
    new_players =
      case {Player.was_stabbed(p1, p2), Player.was_stabbed(p2, p1)} do
        {true, true} -> Player.new_pair_at_x_pos(floor((p1x + p2x) / 2))
        {true, false} -> [Player.new(0, p2x - @death_distance), p2]
        {false, true} -> [p1, Player.new(1, p2x + @death_distance)]
        _ -> [p1, p2]
      end

    %Round{round | players: new_players}
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
    |> game_events()
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
    |> Enum.reduce(canvas, fn %Player{} = player, canvas ->
      player
      |> Player.player_pixels()
      |> Enum.reduce(canvas, fn pix, c ->
        c |> Canvas.put_pixel(Player.to_pix(pix), player.base_color)
      end)
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
