defmodule Octopus.Apps.Hogg.Round do
  defstruct [:t, :players, :canvas]
  alias Octopus.Apps.Hogg
  alias Hogg.Round
  alias Hogg.JoyState
  alias Hogg.Util
  alias Octopus.ColorPalette
  alias Octopus.Canvas

  defmodule Player do
    defstruct pos: {39, 1}, vel: {0, 0}, base_color: [128, 255, 128], is_ducking: false

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

  def tick(%Round{t: t, players: [p1, p2]} = round, [joy1, joy2]) do
    gravity = 0.006
    horz_acc = 0.01
    horz_max = 0.20
    jump = -0.2

    players =
      [{p1, joy1}, {p2, joy2}]
      |> Enum.map(fn {%Player{pos: {x, y}, vel: {dx, dy}} = p, %JoyState{} = joy} ->
        %Player{
          p
          | vel: {
              cond do
                JoyState.button?(joy, :l) -> dx - horz_acc
                JoyState.button?(joy, :r) -> dx + horz_acc
                true -> dx * 0.5
              end
              |> Util.clamp(horz_max),
              cond do
                dy >= 0 and (JoyState.button?(joy, :a) or JoyState.button?(joy, :u)) ->
                  jump

                true ->
                  if y < 7 do
                    dy + gravity
                  else
                    0
                  end
              end
            },
            is_ducking: joy |> JoyState.button?(:d)
        }
      end)
      # apply vel
      |> Enum.map(fn %Player{pos: {x, y}, vel: {dx, dy}} = p ->
        %Player{p | pos: {(x + dx) |> Util.clamp(0, 79), (y + dy) |> Util.clamp(0, 7)}}
      end)

    %Round{round | t: t + 1, players: players}
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
