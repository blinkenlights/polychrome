defmodule Octopus.Apps.BomberPerson.Maps do
  require Logger
  @moduledoc """
  Provides bomber person maps.
  """

  def random_map(), do: maps() |> Enum.random()

  def maps() do
    # This is the map in a format that is convenient for humans to write and understand.
    # The code below transforms it into a datastructure that allows more performant acces during game-play.
    #
    # Legend:
    #   :s = stone
    #   :c = crate
    #   :_ = empty
    #   :g = green start position (Each map should always have exactly one.)
    #   :b = blue start position (Each map should always have exactly one.)
    maps = [
      [
        :g, :_, :_, :c, :_, :c, :_, :c,
        :_, :s, :c, :s, :c, :s, :c, :s,
        :_, :c, :_, :c, :_, :s, :c, :s,
        :c, :s, :c, :s, :c, :_, :_, :_,
        :_, :_, :_, :c, :s, :c, :s, :c,
        :s, :c, :s, :_, :c, :_, :c, :_,
        :s, :c, :s, :c, :s, :c, :s, :_,
        :c, :_, :c, :_, :c, :_, :_, :b,
      ],
    ]

    maps = for map <- maps do
      map
      |> Enum.chunk_every(8)
      |> Enum.with_index()
      |> Enum.flat_map(fn
        {row, y} -> Enum.with_index(row, fn
          :c, x -> {{x, y}, :crate}
          :s, x -> {{x, y}, :stone}
          :_, _ -> {:none, :none}
          player, x -> {{x, y}, player}
        end)
      end)
      |> Enum.filter(fn {:none, _} -> false; _ -> true end)
      |> Map.new()
    end

    player_spawns = for map <- maps do
      for color <- [:g, :b] do
        Enum.find_value(map, fn {coordinate, ^color} -> coordinate; _ -> false end)
      end
    end

    maps = for {map, spawns} <- Enum.zip(maps, player_spawns) do
      Enum.reduce(spawns, map, fn spawn_coordinate, map -> Map.delete(map, spawn_coordinate) end)
    end

    Enum.zip(maps, player_spawns)
  end
end
