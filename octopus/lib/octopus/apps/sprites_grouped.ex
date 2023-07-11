defmodule Octopus.Apps.SpritesGrouped do
  use Octopus.App
  require Logger

  alias Octopus.{Sprite, Canvas, Transitions}

  defmodule State do
    defstruct [:canvas, :group_index, :current_sprites, :sprite_queue, :skip, :palette]
  end

  @sprite_sheet Sprite.list_sprite_sheets() |> hd()

  @easing_interval 150

  @animation_interval 15
  @animation_steps 50

  @tick_interval 500
  @skip_till_next_group 100

  @groups [
    mario: [0..7, 9, 12],
    # donkey_kong: [14, 15],
    # pokemon: [20..24],
    pacman: [56..59],
    # sonic: [64..66],
    # lemming: [68],
    ninja_turtles: [70..73],
    # dexter: [89, 90],
    # futurama: [91..93],
    simpsons: [99..103, 105, 107, 109..111],
    # flintstones: [128..132],
    southpark: [140..143],
    powerrangers: [144..149],
    looney_toons: [150..159],
    disney: [208..215],
    # waldo: [220],
    marvel: [221..225, 228..232],
    starwars: [240..247]

    # powerpuff: [111..113],
    # marvel: [114..120],
    # ghostbusters: [121..125],
    # scoobydoo: [126..130],
    # masters_of_the_unverse: [136..139],
    # dragonball: [95..96],
    # denver: [140],
    # inspector_gadget: [144..146],
    # steven_universe: [147..150],
    # thundercats: [151..154]
    # gundam: [161],
    # chipndale: [162..165],
    # transformers: [166..168],
    # totoro: [169]
    # grendizer: [170],
    # cobra: [181]
    # city_hunter: [182],
    # akira: [183..184],
    # ranma: [185],
    # sailor_moon: [186..190],
    # saint_seiya: [195..200]
  ]

  def name(), do: "Sprite Groups"

  def init(_args) do
    %Canvas{palette: palette} = Sprite.load(@sprite_sheet, 0)

    state =
      %State{
        group_index: 0,
        skip: 0,
        canvas: Canvas.new(80, 8, palette),
        current_sprites: %{},
        palette: palette
      }
      |> queue_sprites()

    :timer.send_interval(@tick_interval, :tick)

    {:ok, state}
  end

  def handle_info(:tick, %State{skip: skip} = state) when skip > 1 do
    {:noreply, %State{state | skip: skip - 1}}
  end

  def handle_info(:tick, %State{skip: 1} = state) do
    empty_canvas = Canvas.new(80, 8, state.palette)

    Transitions.push(state.canvas, empty_canvas, direction: :bottom, steps: @animation_steps)
    |> Stream.map(fn canvas ->
      :timer.sleep(@animation_interval)

      canvas
      |> Canvas.to_frame(easing_interval: @easing_interval)
      |> send_frame()
    end)
    |> Stream.run()

    {:noreply, %State{state | skip: 0, canvas: empty_canvas}}
  end

  def handle_info(:tick, %State{sprite_queue: []} = state) do
    next_index = rem(state.group_index + 1, length(@groups))

    state =
      %State{
        state
        | group_index: next_index,
          skip: @skip_till_next_group
      }
      |> queue_sprites()

    {:noreply, state}
  end

  def handle_info(:tick, %State{sprite_queue: [{window, next_sprite} | rest_sprites]} = state) do
    current_canvas = Canvas.cut(state.canvas, {window * 8, 0}, {window * 8 + 8 - 1, 8 - 1})
    next_cavnas = load_sprite(next_sprite, state.palette)
    # direction = Enum.random([:left, :right, :top, :bottom])
    direction = :top

    Transitions.push(current_canvas, next_cavnas, direction: direction, steps: @animation_steps)
    |> Stream.map(fn window_canvas ->
      state.canvas
      |> Canvas.overlay(window_canvas, offset: {window * 8, 0}, transparency: false)
      |> Canvas.to_frame(easing_interval: @easing_interval)
    end)
    |> Stream.map(fn frame ->
      :timer.sleep(@animation_interval)
      send_frame(frame)
    end)
    |> Stream.run()

    canvas =
      Canvas.overlay(state.canvas, next_cavnas, offset: {window * 8, 0}, transparency: false)

    {:noreply,
     %State{
       state
       | sprite_queue: rest_sprites,
         current_sprites: Map.put(state.current_sprites, window, next_sprite),
         canvas: canvas
     }}
  end

  defp queue_sprites(%State{group_index: index, current_sprites: current_sprites} = state) do
    {_name, indices} = Enum.at(@groups, index)

    queue =
      indices
      |> Enum.flat_map(fn
        index when is_number(index) -> [index]
        list -> Enum.to_list(list)
      end)
      |> place_sprites()
      |> Enum.with_index(fn sprite, index -> {index, sprite} end)
      |> Enum.reject(fn {index, sprite} -> Map.get(current_sprites, index) == sprite end)
      |> Enum.reject(fn {_, sprite} -> sprite == nil end)
      |> Enum.shuffle()

    %State{state | sprite_queue: queue}
  end

  defp place_sprites([]), do: []
  defp place_sprites([a]), do: [nil, nil, nil, nil, a, nil, nil, nil, nil, nil]
  defp place_sprites([a, b]), do: [nil, nil, nil, a, nil, nil, b, nil, nil, nil]
  defp place_sprites([a, b, c]), do: [nil, nil, a, nil, nil, b, nil, nil, c, nil]
  defp place_sprites([a, b, c, d]), do: [nil, a, nil, b, nil, c, nil, d, nil, nil]
  defp place_sprites([a, b, c, d, e]), do: [a, nil, b, nil, c, nil, d, nil, e, nil]
  defp place_sprites([a, b, c, d, e, f]), do: [nil, a, b, nil, c, d, nil, e, f, nil]
  defp place_sprites([a, b, c, d, e, f, g]), do: [a, b, nil, c, d, nil, e, f, nil, g]
  defp place_sprites([a, b, c, d, e, f, g, h]), do: [nil, a, b, c, d, e, f, g, h, nil]
  defp place_sprites([a, b, c, d, e, f, g, h, i]), do: [a, b, c, d, e, f, g, h, i, nil]
  defp place_sprites([a, b, c, d, e, f, g, h, i, j]), do: [a, b, c, d, e, f, g, h, i, j]
  # defp place_sprites(list), do: Enum.take_random(list, 10) |> place_sprites()

  defp load_sprite(nil, palette), do: Canvas.new(8, 8, palette)
  defp load_sprite(index, _palette), do: Sprite.load(@sprite_sheet, index)
end
