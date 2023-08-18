defmodule Octopus.Apps.Blocks.Game do
  defstruct score: 0, layout: %{}, moved: false, t: 0
  alias Octopus.Font
  alias Octopus.Sprite
  alias Octopus.Canvas
  alias Octopus.JoyState
  alias Octopus.Apps.Blocks
  alias Blocks.Game

  def new(args) do
    title = Canvas.from_string("T", Font.load("robot"))

    %Game{
      layout:
        case args[:layout] do
          nil ->
            unless args[:side] == :right do
              %{
                base_canvas: Canvas.new(40, 8) |> Canvas.overlay(title),
                score_base: 16,
                playfield_base: 8 * 4,
                playfield_channel: 5
              }
            else
              %{
                base_canvas:
                  Canvas.new(40, 8)
                  |> Canvas.overlay(title, offset: {4 * 8, 0}),
                score_base: 24,
                playfield_base: 0,
                playfield_channel: 6
              }
            end

          layout when layout != nil ->
            layout
        end
    }
  end

  def tick(%Game{} = game, _joy) do
    %Game{
      case rem(game.t, 60) do
        0 -> %Game{game | score: game.score + 1}
        _ -> game
      end
      | t: game.t + 1
    }
  end

  def render_canvas(%Game{layout: layout} = game) do
    [first, second] =
      game.score |> to_string() |> String.pad_leading(2, "0") |> String.to_charlist()

    font = Font.load("robot")
    font_variant = 8

    canvas =
      layout.base_canvas
      #      |> Canvas.overlay(gamecanvas, offset: {layout.playfield_base, 0})
      |> Font.pipe_draw_char(font, second, font_variant, {layout.score_base, 0})
      |> (fn c ->
            unless first == ?0 do
              c |> Font.pipe_draw_char(font, first, font_variant, {layout.score_base - 8, 0})
            else
              c
            end
          end).()

    canvas
  end
end
