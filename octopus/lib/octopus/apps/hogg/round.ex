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
              is_ducking: false,
              can_jump: false,
              last_jump: -100

    def new(0) do
      %Player{pos: {8 * 3 + 4, 1}}
    end

    def new(1) do
      %Player{pos: {8 * 6 + 3, 1}, base_color: [255, 128, 128]}
    end
  end

  def new() do
    %Round{t: 0, canvas: Canvas.new(80, 8), players: [Player.new(0), Player.new(1)]}
  end

  @horz_acc 0.01
  @horz_max 0.20
  @jump -1
  @gravity 0.006

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
            is_ducking: joy |> JoyState.button?(:d),
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

  defp collsion_detection(%Round{players: players} = round) do
    players =
      players
      |> Enum.map(fn %Player{pos: {x, y}, vel: {dx, dy}} = p ->
        {tx, ty} = {x + dx, y + dy}

        clampx_max = round.canvas.width - 1
        clampx_min = 0

        {new_x, new_dx} =
          cond do
            round(tx) >= clampx_max and dx > 0 -> {clampx_max, 0}
            round(tx) <= clampx_min and dx < 0 -> {clampx_min, 0}
            true -> {x, dx}
          end

        clampy_max = 7
        clampy_min = 0

        {new_y, new_dy} =
          cond do
            round(ty) >= clampy_max and dy > 0 -> {clampy_max, 0}
            round(ty) <= clampy_min and dy < 0 -> {clampy_min, 0}
            true -> {y, dy}
          end

        %Player{p | pos: {new_x, new_y}, vel: {new_dx, new_dy}, can_jump: new_dy == 0 and dy > 0}
      end)

    %Round{round | players: players}
  end

  defp apply_movement(%Round{players: players} = round) do
    # apply vel
    players =
      players
      |> Enum.map(fn %Player{pos: {x, y}, vel: {dx, dy}} = p ->
        %Player{p | pos: {x + dx, y + dy}}
      end)

    %Round{round | players: players}
  end

  def tick(%Round{t: t, players: [p1, p2]} = round, [joy1, joy2] = joylist) do
    round
    |> apply_input(joylist)
    |> apply_physics()
    |> collsion_detection()
    |> apply_movement()
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
      x = floor(x)
      y = floor(y)

      canvas
      |> Canvas.put_pixel({x, y}, player.base_color)
      |> (fn
            c, true -> c
            c, false -> c |> Canvas.put_pixel({x, y - 1}, player.base_color)
          end).(player.is_ducking)
    end)
    |> Canvas.to_frame()
  end
end
