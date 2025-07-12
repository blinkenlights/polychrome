defmodule Octopus.Apps.BomberPerson do
  use Octopus.App, category: :game
  require Logger

  alias Octopus.Apps.BomberPerson.Maps
  alias Octopus.{Canvas, Util, Font}
  alias Octopus.Events.Event.Input, as: InputEvent

  defmodule State do
    defstruct [
      :game_state,
      :wait_ticks,
      :canvas,
      :score_canvas,
      :big_canvas,
      :font,
      :players,
      :map,
      :bombs,
      :explosions
    ]
  end

  defmodule Player do
    defstruct [:position, :color, :score]
  end

  defmodule Bomb do
    defstruct [:remaining_ticks, :player_index]
  end

  defmodule Explosion do
    defstruct [:position, :remaining_ticks]
  end

  @fps 60
  @bombs_per_player 2
  @bomb_ticks 150
  @explosion_ticks 45
  # @explosion_range 2 TODO: Implement
  @grid_size 8
  @game_over_wait 80
  @font_name "1943"
  @font_variants %{0 => 6, 1 => 5}

  def color(:stone), do: {150, 150, 150}
  def color(:crate), do: {80, 57, 0}
  def color(:bomb), do: {180, 0, 0}
  def color(:explosion), do: {255, 150, 0}
  def color(:player_0_victory), do: {0, 180, 0}
  def color(:player_1_victory), do: {0, 0, 180}
  def color(_), do: {255, 255, 255}

  def name(), do: "Bomber Person"

  def compatible?() do
    installation_info = Octopus.App.get_installation_info()

    installation_info.panel_count == 10 and
      installation_info.panel_width == 8 and
      installation_info.panel_height == 8 and
      installation_info.num_joysticks == 2
  end

  def app_init(_args) do
    # Configure display using new unified API - adjacent layout (was Canvas.to_frame())
    Octopus.App.configure_display(layout: :adjacent_panels)

    state = create_state()

    :timer.send_interval(trunc(1000 / @fps), :tick)

    {:ok, state}
  end

  def create_state(previous_state \\ nil) do
    {map, [spawn_1, spawn_2]} = Maps.random_map()

    %State{
      game_state: :running,
      wait_ticks: 0,
      canvas: Canvas.new(8, 8),
      score_canvas: %{0 => Canvas.new(16, 8), 1 => Canvas.new(16, 8)},
      big_canvas: Canvas.new(80, 8),
      font: Font.load(@font_name),
      players: %{
        0 => %Player{
          position: spawn_1,
          color: {0, 255, 0},
          score: if(previous_state == nil, do: 0, else: previous_state.players[0].score)
        },
        1 => %Player{
          position: spawn_2,
          color: {0, 0, 255},
          score: if(previous_state == nil, do: 0, else: previous_state.players[1].score)
        }
      },
      bombs: %{},
      explosions: [],
      map: map
    }
  end

  def handle_info(:tick, %State{game_state: game_state} = state) do
    case game_state do
      :running -> update_game(state)
      :pause_player_0_victory -> handle_pause(state)
      :pause_player_1_victory -> handle_pause(state)
      :player_0_victory -> show_victory(state)
      :player_1_victory -> show_victory(state)
    end
  end

  def handle_pause(%State{game_state: game_state, wait_ticks: wait_ticks} = state) do
    {wait_ticks, game_state} =
      if wait_ticks > 0 do
        {wait_ticks, game_state}
      else
        case game_state do
          :pause_player_0_victory -> {@game_over_wait, :player_0_victory}
          :pause_player_1_victory -> {@game_over_wait, :player_1_victory}
          # unreachable
          _ -> {0, :running}
        end
      end

    state =
      %State{state | wait_ticks: wait_ticks - 1, game_state: game_state}
      |> render_canvas()

    {:noreply, state}
  end

  def show_victory(%State{game_state: game_state, canvas: canvas, wait_ticks: wait_ticks} = state) do
    canvas =
      canvas
      |> Canvas.clear()
      |> Canvas.fill_rect({0, 0}, {@grid_size - 1, @grid_size - 1}, color(game_state))

    if wait_ticks > 0 do
      state =
        %State{state | canvas: canvas, wait_ticks: wait_ticks - 1}
        |> combine_and_send_canvas()

      {:noreply, state}
    else
      {:noreply, create_state(state)}
    end
  end

  def update_game(
        %State{
          game_state: game_state,
          bombs: bombs,
          map: map,
          players: players,
          explosions: explosions
        } = state
      ) do
    # Explode bombs and create explosion tiles.
    new_explosions = for {coordinate, bomb} <- bombs, bomb.remaining_ticks <= 0, do: coordinate
    map = Enum.reduce(new_explosions, map, fn coordinate, map -> Map.delete(map, coordinate) end)

    new_explosions =
      List.flatten(
        for coordinate <- new_explosions do
          explode(coordinate, map)
        end
      )

    explosions = explosions ++ new_explosions

    # Explode crates.
    map =
      Enum.reduce(new_explosions, map, fn
        %Explosion{position: coordinate}, map ->
          case map do
            %{^coordinate => :crate} -> Map.delete(map, coordinate)
            _ -> map
          end
      end)

    # Explode players.
    player_0_position = players[0].position
    player_1_position = players[1].position

    game_state =
      Enum.reduce(explosions, game_state, fn %Explosion{position: coordinate}, game_state ->
        case game_state do
          :running when coordinate == player_0_position -> :pause_player_1_victory
          :running when coordinate == player_1_position -> :pause_player_0_victory
          _ -> game_state
        end
      end)

    wait_ticks = if game_state == :running, do: 0, else: @game_over_wait

    # Increase player score on victory.
    players =
      if game_state == :running do
        players
      else
        player_index =
          case game_state do
            :pause_player_0_victory -> 0
            :pause_player_1_victory -> 1
          end

        player = players[player_index]
        Map.put(players, player_index, %Player{player | score: player.score + 1})
      end

    # Tick bombs and explosion tiles.
    bombs =
      for {coordinate, bomb} <- bombs, bomb.remaining_ticks > 0, into: %{} do
        {coordinate, %Bomb{bomb | remaining_ticks: bomb.remaining_ticks - 1}}
      end

    explosions =
      for explosion <- explosions, explosion.remaining_ticks > 0 do
        %Explosion{explosion | remaining_ticks: explosion.remaining_ticks - 1}
      end

    state =
      %State{
        state
        | game_state: game_state,
          bombs: bombs,
          explosions: explosions,
          map: map,
          players: players,
          wait_ticks: wait_ticks
      }
      |> render_canvas()

    {:noreply, state}
  end

  def render_canvas(state) do
    canvas = state.canvas |> Canvas.clear()

    canvas =
      Enum.reduce(state.map, canvas, fn {coordinate, cell}, canvas ->
        canvas |> Canvas.put_pixel(coordinate, color(cell))
      end)

    canvas =
      Enum.reduce(state.explosions, canvas, fn %Explosion{position: coordinate}, canvas ->
        canvas |> Canvas.put_pixel(coordinate, color(:explosion))
      end)

    canvas =
      Enum.reduce(state.players, canvas, fn {_, player}, canvas ->
        canvas |> Canvas.put_pixel(player.position, player.color)
      end)

    %State{state | canvas: canvas}
    |> render_score(0)
    |> render_score(1)
    |> combine_and_send_canvas()
  end

  def render_score(%State{font: font} = state, player_index) do
    score = state.players[player_index].score

    [first_char, second_char] =
      score
      |> to_string()
      |> String.pad_leading(2, "0")
      |> String.to_charlist()

    font_variant = @font_variants[player_index]

    canvas =
      state.score_canvas[player_index]
      |> Canvas.clear()
      |> Font.pipe_draw_char(font, first_char, font_variant)
      |> Font.pipe_draw_char(font, second_char, font_variant, {8, 0})

    %State{state | score_canvas: Map.put(state.score_canvas, player_index, canvas)}
  end

  def combine_and_send_canvas(state) do
    big_canvas =
      state.big_canvas
      |> Canvas.clear()
      |> Canvas.overlay(state.score_canvas[0], offset: {24, 0})
      |> Canvas.overlay(state.canvas, offset: {40, 0})
      |> Canvas.overlay(state.score_canvas[1], offset: {48, 0})

    Octopus.App.update_display(big_canvas)

    %State{state | big_canvas: big_canvas}
  end

  def explode(coordinate, map) do
    [%Explosion{position: coordinate, remaining_ticks: @explosion_ticks}] ++
      explode(coordinate, {1, 0}, map) ++
      explode(coordinate, {-1, 0}, map) ++
      explode(coordinate, {0, 1}, map) ++
      explode(coordinate, {0, -1}, map)
  end

  def explode({x, y}, {dx, dy}, map) do
    x = x + dx
    y = y + dy

    explosion = %Explosion{position: {x, y}, remaining_ticks: @explosion_ticks}

    cond do
      x < 0 || x >= @grid_size || y < 0 || y >= @grid_size -> []
      Map.has_key?(map, {x, y}) && map[{x, y}] == :crate -> [explosion]
      Map.has_key?(map, {x, y}) -> []
      true -> [explosion | explode({x, y}, {dx, dy}, map)]
    end
  end

  def place_bomb(state, player_index) do
    coordinate = state.players[player_index].position

    bomb_count =
      state.bombs
      |> Enum.count(fn
        {_, %Bomb{player_index: ^player_index}} -> true
        _ -> false
      end)

    if state.game_state == :running && bomb_count < @bombs_per_player do
      new_bomb = %Bomb{remaining_ticks: @bomb_ticks, player_index: player_index}

      {:noreply,
       %State{
         state
         | map: state.map |> Map.put(coordinate, :bomb),
           bombs: state.bombs |> Map.put(coordinate, new_bomb)
       }}
    else
      {:noreply, state}
    end
  end

  def handle_event(
        %InputEvent{type: :joystick, joystick: joystick, joy_button: :a, action: :press},
        state
      ) do
    # Convert to 0-based player index
    place_bomb(state, joystick - 1)
  end

  def handle_event(
        %InputEvent{type: :joystick, joystick: joystick, direction: direction},
        state
      )
      when direction in [:left, :right, :up, :down] do
    if state.game_state == :running do
      move_player(state, joystick - 1, direction)
    else
      {:noreply, state}
    end
  end

  def handle_event(
        %InputEvent{type: :joystick, joystick: _joystick, direction: :center},
        state
      ) do
    # Joystick returned to center - no movement needed
    {:noreply, state}
  end

  def handle_event(_event, state) do
    {:noreply, state}
  end

  defp move_player(state, player_index, direction) do
    player = state.players[player_index]
    %Player{position: {player_x, player_y}} = player

    {dx, dy} = direction_to_delta(direction)
    {new_x, new_y} = {player_x + dx, player_y + dy}

    position = {
      new_x |> Util.clamp(0, @grid_size - 1),
      new_y |> Util.clamp(0, @grid_size - 1)
    }

    position =
      cond do
        state.map |> Map.has_key?(position) ->
          player.position

        state.players |> Enum.any?(fn {_, other} -> position == other.position end) ->
          player.position

        true ->
          position
      end

    player = %Player{player | position: position}
    new_state = %State{state | players: state.players |> Map.put(player_index, player)}
    {:noreply, new_state}
  end

  # Convert semantic direction to coordinate delta
  defp direction_to_delta(:left), do: {-1, 0}
  defp direction_to_delta(:right), do: {1, 0}
  defp direction_to_delta(:up), do: {0, -1}
  defp direction_to_delta(:down), do: {0, 1}
end
