defmodule Octopus.Apps.Blocks.Game do
  alias Octopus.Canvas
  defstruct tile: nil, board: Canvas.new(8, 16), score: 0, layout: %{}, moved: false, t: 0
  alias Phoenix.LiveDashboard.TitleBarComponent
  alias Octopus.Font
  alias Octopus.Sprite
  alias Octopus.JoyState
  alias Octopus.Apps.Blocks
  alias Blocks.Game

  defmodule Tile do
    defstruct pos: {3, -2}, index: 0, rotations: [], col: nil, t_rem: 20

    def new(rotations, col) do
      %Tile{
        rotations: rotations,
        col: col
      }
    end

    def tile_canvas(%Tile{index: index, rotations: rotations, col: col}) do
      rotations
      |> Enum.at(index)
      |> Enum.with_index()
      |> Enum.reduce(Canvas.new(4, 4), fn {row, y}, acc ->
        row
        |> Enum.with_index()
        |> Enum.reduce(acc, fn
          {0, _}, acc -> acc
          {1, x}, acc -> acc |> Canvas.put_pixel({x, y}, col)
        end)
      end)
    end

    def move(%Tile{pos: {x, y}} = tile) do
      %Tile{
        tile
        | pos: {x, y + 1}
      }
    end
  end

  @tiles Code.eval_string("""
         [
         [
         [[0, 0, 0, 0],
         [0, 0, 0, 0],
         [0, 0, 1, 1],
         [0, 1, 1, 0]],
         [[0, 0, 0, 0],
         [0, 1, 0, 0],
         [0, 1, 1, 0],
         [0, 0, 1, 0]]
         ],
         [
           [[0, 1, 0, 0],
           [0, 1, 0, 0],
           [0, 1, 0, 0],
           [0, 1, 0, 0]],
           [[0, 0, 0, 0],
           [0, 0, 0, 0],
           [1, 1, 1, 1],
           [0, 0, 0, 0]]
           ],
         ]
         """)
         |> elem(0)

  @colors [
    {219, 59, 57},
    {235, 155, 62},
    {248, 226, 76},
    {106, 181, 85},
    {84, 170, 221},
    {36, 87, 153},
    {135, 47, 136}
  ]

  def new_tile() do
    Tile.new(
      @tiles |> Enum.random(),
      @colors |> Enum.random()
    )
  end

  def new(args) do
    title = Canvas.from_string("T", Font.load("robot"))

    %Game{
      tile: new_tile(),
      layout:
        case args[:layout] do
          nil ->
            unless args[:side] == :right do
              %{
                base_canvas: Canvas.new(40, 8) |> Canvas.overlay(title),
                score_base: 16,
                playfield_base: 8 * 3,
                playfield_channel: 5,
                playfield_rotation: :ccw
              }
            else
              %{
                base_canvas:
                  Canvas.new(40, 8)
                  |> Canvas.overlay(title, offset: {4 * 8, 0}),
                score_base: 24,
                playfield_base: 0,
                playfield_channel: 6,
                playfield_rotation: :cw
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
        0 -> %Game{game | score: game.score + 1, tile: game.tile |> Tile.move()}
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

    gamecanvas =
      game.board
      |> Canvas.overlay(Tile.tile_canvas(game.tile))
      |> Canvas.rotate(layout.playfield_rotation)

    canvas =
      layout.base_canvas
      |> Canvas.overlay(gamecanvas, offset: {layout.playfield_base, 0})
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
