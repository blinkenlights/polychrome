defmodule Octopus.Apps.SpritesGrouped do
  use Octopus.App, category: :animation

  alias Octopus.{Sprite, Canvas, Transitions}

  defmodule State do
    defstruct [
      :group_index,
      :current_sprites,
      :sprite_queue,
      :skip,
      :panel_width,
      :num_panels
    ]
  end

  @sprite_sheet "256-characters-original"

  @easing_interval 250

  @animation_interval 15
  @animation_steps 50

  @tick_interval 500
  @skip_till_next_group 10

  @groups [
    mario: [0..7, 9, 12],
    pokemon: [20..26],
    pacman: [56..59],
    # sonic: [64..67],
    ninja_turtles: [70..73],
    # futurama: [91..93],
    simpsons: [99..103, 105, 107, 109..111],
    # flintstones: [128..132],
    southpark: [140..143],
    powerrangers: [144..149],
    looney_toons: [150..159],
    disney: [208..215],
    marvel: [221..225, 228..232],
    starwars: [240..247]
    # kirby: [13],
    # donkey_kong: [14, 15],
    # link: [16],
    # rayman: [47],
    # lemming: [68],
    # dexter: [89, 90],
    # waldo: [220],
    # others: [13, 14, 16, 68, 47, 220]

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

  def compatible?() do
    # Sprites are designed for 8x8 panels - cropping makes them unrecognizable
    installation_info = Octopus.App.get_installation_info()

    # Require exactly 8x8 panels for optimal sprite display
    installation_info.panel_width >= 8 and installation_info.panel_height >= 8
  end

  def app_init(_args) do
    # Configure display using new unified API - adjacent layout for panel joining
    # Use smooth easing for sprite transitions
    Octopus.App.configure_display(layout: :adjacent_panels, easing_interval: @easing_interval)

    # Get dynamic dimensions from display info
    installation_info = Octopus.App.get_installation_info()
    sprite_panel_width = trunc(installation_info.panel_width)
    num_panels = installation_info.panel_count

    state =
      %State{
        group_index: 0,
        skip: 0,
        panel_width: sprite_panel_width,
        num_panels: num_panels,
        current_sprites: %{}
      }
      |> queue_sprites()

    :timer.send_interval(@tick_interval, :tick)

    {:ok, state}
  end

  def handle_info(:tick, %State{skip: skip} = state) when skip > 1 do
    {:noreply, %State{state | skip: skip - 1}}
  end

  def handle_info(:tick, %State{skip: 1} = state) do
    # Create empty canvas by joining empty panel canvases
    empty_canvas = create_final_canvas(%{}, state.num_panels, state.panel_width)

    Octopus.App.update_display(empty_canvas)

    {:noreply, %State{state | skip: 0}}
  end

  def handle_info(:tick, %State{sprite_queue: []} = state) do
    next_index = rem(state.group_index + 1, length(@groups))

    state =
      %State{
        state
        | group_index: next_index,
          skip: @skip_till_next_group,
          # Clear current sprites when switching groups
          current_sprites: %{}
      }
      |> queue_sprites()

    {:noreply, state}
  end

  def handle_info(
        :tick,
        %State{sprite_queue: [{panel_index, next_sprite} | rest_sprites]} = state
      ) do
    # Get the current and next sprite canvases for this panel
    current_sprite = Map.get(state.current_sprites, panel_index)
    current_panel_canvas = load_sprite(current_sprite, state.panel_width)
    next_panel_canvas = load_sprite(next_sprite, state.panel_width)

    # Pre-load all static panel canvases once (optimization)
    static_panel_canvases =
      0..(state.num_panels - 1)
      |> Enum.map(fn idx ->
        if idx == panel_index do
          # Will be replaced with animated canvas
          nil
        else
          sprite_index = Map.get(state.current_sprites, idx)
          load_sprite(sprite_index, state.panel_width)
        end
      end)

    # Animate the transition for this specific panel
    direction = :top

    Transitions.push(current_panel_canvas, next_panel_canvas,
      direction: direction,
      steps: @animation_steps
    )
    |> Stream.map(fn animated_panel_canvas ->
      # Use pre-loaded static canvases, only replace the animated one
      panel_canvases =
        static_panel_canvases
        |> List.replace_at(panel_index, animated_panel_canvas)

      # Join all panels and update display
      final_canvas =
        panel_canvases
        |> Enum.reduce(&Canvas.join(&2, &1))

      Octopus.App.update_display(final_canvas)

      :timer.sleep(@animation_interval)
    end)
    |> Stream.run()

    # Update the current sprites map and send final frame
    new_current_sprites = Map.put(state.current_sprites, panel_index, next_sprite)

    # The final frame is the last animation frame, no need to create it again
    {:noreply,
     %State{
       state
       | sprite_queue: rest_sprites,
         current_sprites: new_current_sprites
     }}
  end

  defp queue_sprites(
         %State{
           group_index: index,
           current_sprites: current_sprites,
           num_panels: num_panels
         } = state
       ) do
    {_name, indices} = Enum.at(@groups, index)

    # Get the sprites for this group
    group_sprites =
      indices
      |> Enum.flat_map(fn
        index when is_number(index) -> [index]
        list -> Enum.to_list(list)
      end)

    # Place sprites in their positions
    positioned_sprites = place_sprites(group_sprites, num_panels)

    # Create queue of sprites that need to be updated
    all_positioned =
      positioned_sprites |> Enum.with_index(fn sprite, panel_index -> {panel_index, sprite} end)

    after_filter =
      all_positioned
      |> Enum.reject(fn {panel_index, sprite} ->
        # Only reject if the exact same sprite is already in the exact same position
        Map.get(current_sprites, panel_index) == sprite
      end)

    after_nil_filter = after_filter |> Enum.reject(fn {_, sprite} -> sprite == nil end)

    queue = after_nil_filter |> Enum.shuffle()

    %State{state | sprite_queue: queue}
  end

  defp place_sprites([], _num_windows), do: []

  defp place_sprites(sprites, num_windows) when length(sprites) >= num_windows do
    Enum.take(sprites, num_windows)
  end

  defp place_sprites(sprites, num_panels) do
    sprite_count = length(sprites)

    cond do
      sprite_count == num_panels ->
        # Special case: if we have exactly as many sprites as panels, place one in each panel
        sprites

      sprite_count > num_panels / 2 ->
        # If we have more than half the panels, place them consecutively centered
        padding = div(num_panels - sprite_count, 2)

        List.duplicate(nil, padding) ++
          sprites ++ List.duplicate(nil, num_panels - sprite_count - padding)

      true ->
        # If we have fewer than half the panels, distribute them evenly across the space
        positions = distribute_evenly(sprite_count, num_panels)

        # Create result array and place sprites at calculated positions
        result = List.duplicate(nil, num_panels)

        sprites
        |> Enum.zip(positions)
        |> Enum.reduce(result, fn {sprite, pos}, acc ->
          List.replace_at(acc, pos, sprite)
        end)
    end
  end

  # Distribute sprites evenly across available panels
  defp distribute_evenly(sprite_count, num_panels) do
    if sprite_count == 1 do
      # Single sprite goes in the center
      [div(num_panels - 1, 2)]
    else
      # For multiple sprites, distribute them evenly with better spacing
      case sprite_count do
        2 ->
          # For 2 sprites in 12 panels, use positions like 3, 8 (1-indexed: 4, 9)
          quarter = div(num_panels, 4)
          [quarter, num_panels - quarter - 1]

        3 ->
          # For 3 sprites, use positions like 2, 5, 8 (1-indexed: 3, 6, 9)
          step = div(num_panels - 1, 3)
          [step, step * 2, step * 3]

        4 ->
          # For 4 sprites in 12 panels, use positions like 1, 4, 7, 10 (1-indexed: 2, 5, 8, 11)
          step = div(num_panels - 1, 4)
          [step, step * 2, step * 3, step * 4]

        _ ->
          # For other counts, distribute evenly
          step = max(1, div(num_panels - 1, sprite_count - 1))

          0..(sprite_count - 1)
          |> Enum.map(fn i -> min(i * step, num_panels - 1) end)
      end
    end
  end

  # Create the final canvas by joining individual panel canvases - like pixel_fun does
  defp create_final_canvas(current_sprites, num_panels, panel_width) do
    0..(num_panels - 1)
    |> Enum.map(fn panel_index ->
      sprite_index = Map.get(current_sprites, panel_index)
      load_sprite(sprite_index, panel_width)
    end)
    |> Enum.reduce(&Canvas.join(&2, &1))
  end

  defp load_sprite(nil, panel_width), do: Canvas.new(panel_width, panel_width)

  defp load_sprite(index, panel_width) do
    # Load the original 8x8 sprite
    original_sprite = Sprite.load(@sprite_sheet, index)

    cond do
      panel_width == 8 ->
        # Perfect match, use sprite as-is
        original_sprite

      panel_width > 8 ->
        # Panel is larger than sprite, center the sprite within the panel
        new_canvas = Canvas.new(panel_width, panel_width)
        offset_x = div(panel_width - 8, 2)
        offset_y = div(panel_width - 8, 2)
        Canvas.overlay(new_canvas, original_sprite, offset: {offset_x, offset_y})

      panel_width < 8 ->
        # Panel is smaller than sprite, crop the sprite to fit
        # Note: This may make sprites unrecognizable
        Canvas.cut(original_sprite, {0, 0}, {panel_width - 1, panel_width - 1})
    end
  end
end
