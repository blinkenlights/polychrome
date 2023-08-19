defmodule Octopus.Apps.BomberPersonApp do
  use Octopus.App, category: :game
  require Logger

  alias Octopus.{Canvas, Util}
  alias Octopus.Protobuf.InputEvent

  defmodule State do
    defstruct [:canvas, :players, :map]
  end

  defmodule Player do
    defstruct [:position, :color]
  end

  @fps 60

  @stone_color {150, 150, 150}
  @crate_color {80, 57, 0}

  def name(), do: "Bomber Person"

  def init(_args) do
    state = %State{
      canvas: Canvas.new(8, 8),
      players: %{
        1 => %Player{position: {0, 0}, color: {0, 255, 0}},
        2 => %Player{position: {6, 6}, color: {0, 0, 255}},
      },
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

  def handle_info(:tick, %State{} = state) do
    canvas = state.canvas |> Canvas.clear()

    canvas = Enum.reduce(state.map, canvas,
      fn {coordinate, cell}, canvas ->
        color = if cell == :stone, do: @stone_color, else: @crate_color
        canvas |> Canvas.put_pixel(coordinate, color)
      end)

    canvas = Enum.reduce(state.players, canvas,
      fn {_, player}, canvas -> canvas |> Canvas.put_pixel(player.position, player.color) end)

    canvas
    |> Canvas.to_frame()
    |> send_frame()

    {:noreply, %State{state | canvas: canvas}}
  end

  def handle_input(%InputEvent{type: :BUTTON_A_1, value: 1}, state) do
    {:noreply, state}
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
      player_1_x |> Util.clamp(0, 6),
      player_1_y |> Util.clamp(0, 6),
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
