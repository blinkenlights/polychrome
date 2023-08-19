defmodule Octopus.Apps.BomberPersonApp do
  use Octopus.App, category: :game
  require Logger

  alias Octopus.{Canvas, Util}
  alias Octopus.Protobuf.InputEvent

  defmodule State do
    defstruct [:canvas, :players, :map, :bombs, :explosions]
  end

  defmodule Player do
    defstruct [:position, :color]
  end

  defmodule Bomb do
    defstruct [:remaining_ticks]
  end

  defmodule Explosion do
    defstruct [:position, :remaining_ticks]
  end

  @fps 60
  @bomb_ticks 180
  @explosion_ticks 60
  @explosion_range 2
  @grid_size 6

  def color(:stone), do: {150, 150, 150}
  def color(:crate), do: {80, 57, 0}
  def color(:bomb), do: {180, 0, 0}
  def color(:explosion), do: {255, 150, 0}
  def color(_), do: {255, 255, 255}

  def name(), do: "Bomber Person"

  def init(_args) do
    state = %State{
      canvas: Canvas.new(8, 8),
      players: %{
        1 => %Player{position: {0, 0}, color: {0, 255, 0}},
        2 => %Player{position: {6, 6}, color: {0, 0, 255}},
      },
      bombs: %{},
      explosions: [],
      map: %{
        {3, 0} => :crate,
        {5, 0} => :crate,

        {1, 1} => :stone,
        {2, 1} => :crate,
        {3, 1} => :stone,
        {4, 1} => :crate,
        {5, 1} => :stone,
        {6, 1} => :crate,

        {1, 2} => :crate,
        {3, 2} => :crate,
        {5, 2} => :crate,

        {0, 3} => :crate,
        {1, 3} => :stone,
        {2, 3} => :crate,
        {3, 3} => :stone,
        {4, 3} => :crate,
        {5, 3} => :stone,
        {6, 3} => :crate,

        {1, 4} => :crate,
        {3, 4} => :crate,
        {5, 4} => :crate,

        {0, 5} => :crate,
        {1, 5} => :stone,
        {2, 5} => :crate,
        {3, 5} => :stone,
        {4, 5} => :crate,
        {5, 5} => :stone,

        {1, 6} => :crate,
        {3, 6} => :crate,
      },
    }

    :timer.send_interval(trunc(1000 / @fps), :tick)

    {:ok, state}
  end

  def handle_info(:tick, %State{bombs: bombs, map: map, explosions: explosions} = state) do
    # Explode bombs and create explosion tiles.
    new_explosions = for {coordinate, bomb} <- bombs, bomb.remaining_ticks <= 0, do: coordinate
    map = Enum.reduce(new_explosions, map, fn coordinate, map -> Map.delete(map, coordinate) end)
    new_explosions = List.flatten(for coordinate <- new_explosions do explode(coordinate, map) end)
    explosions = explosions ++ new_explosions

    # Explode crates.
    map = Enum.reduce(new_explosions, map, fn
      %Explosion{position: coordinate}, map ->
        case map do
          %{^coordinate => :crate} -> Map.delete(map, coordinate)
          _ -> map
        end
      end)

    # Tick bombs and explosion tiles.
    bombs = for {coordinate, bomb} <- bombs, bomb.remaining_ticks > 0, into: %{} do
      {coordinate, %Bomb{bomb | remaining_ticks: bomb.remaining_ticks - 1 }}
    end
    explosions = for explosion <- explosions, explosion.remaining_ticks > 0 do
      %Explosion{explosion | remaining_ticks: explosion.remaining_ticks - 1 }
    end

    state = %State{state | bombs: bombs, explosions: explosions, map: map}
    canvas = render_canvas(state)

    {:noreply, %State{state | canvas: canvas}}
  end

  def render_canvas(state) do
    canvas = state.canvas |> Canvas.clear()

    canvas = Enum.reduce(state.map, canvas, fn {coordinate, cell}, canvas ->
      canvas |> Canvas.put_pixel(coordinate, color(cell))
    end)

    canvas = Enum.reduce(state.explosions, canvas, fn %Explosion{position: coordinate}, canvas ->
      canvas |> Canvas.put_pixel(coordinate, color(:explosion))
    end)

    canvas = Enum.reduce(state.players, canvas, fn {_, player}, canvas ->
      canvas |> Canvas.put_pixel(player.position, player.color)
    end)

    canvas
    |> Canvas.to_frame()
    |> send_frame()

    canvas
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
      x < 0 || x > @grid_size || y < 0 || y > @grid_size -> []
      Map.has_key?(map, {x, y}) && map[{x, y}] == :crate -> [explosion]
      Map.has_key?(map, {x, y}) -> []
      true -> [explosion | explode({x, y}, {dx, dy}, map)]
    end
  end

  def handle_input(%InputEvent{type: :BUTTON_A_1, value: 1}, state) do
    coordinate = state.players[1].position

    {:noreply, %State{state |
      map: state.map |> Map.put(coordinate, :bomb),
      bombs: state.bombs |> Map.put(coordinate, %Bomb{remaining_ticks: @bomb_ticks}),
    }}
  end

  def handle_input(%InputEvent{type: type, value: value}, state) do
    player_1 = state.players[1]
    %Player{position: {player_1_x, player_1_y}} = state.players[1]

    {player_1_x, player_1_y} = case type do
      :AXIS_X_1 -> {player_1_x + value, player_1_y}
      :AXIS_Y_1 -> {player_1_x, player_1_y + value}
      _ -> {player_1_x, player_1_y}
    end

    position_1 = {
      player_1_x |> Util.clamp(0, @grid_size),
      player_1_y |> Util.clamp(0, @grid_size),
    }

    position_1 = cond do
      state.map |> Map.has_key?(position_1) -> player_1.position
      true -> position_1
    end

    player_1 = %Player{player_1 | position: position_1}
    {:noreply, %State{state | players: state.players |> Map.put(1, player_1)}}
  end

  def handle_input(_input_event, state) do
    {:noreply, state}
  end

  def handle_control_event(_event, state) do
    {:noreply, state}
  end
end
