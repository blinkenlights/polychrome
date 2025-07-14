defmodule Octopus.Apps.Sand.Sim do
  @enforce_keys [:width, :height, :particles, :spawn_pos, :spawn_pos_dir]
  defstruct [:width, :height, :particles, :spawn_pos, :spawn_pos_dir]

  alias __MODULE__
  alias Octopus.Canvas

  @type particle() :: {:sand, Canvas.color()}

  @type coord() :: {integer(), integer()}

  @type t() :: %__MODULE__{
          width: integer(),
          height: integer(),
          particles: %{required(coord()) => particle()},
          spawn_pos: coord(),
          spawn_pos_dir: integer()
        }

  def new(width, height) do
    %Sim{
      width: width,
      height: height,
      particles: %{},
      spawn_pos: {trunc(width / 2), -1},
      spawn_pos_dir: 1
    }
  end

  def step(%Sim{} = sim, _) do
    hue = :rand.uniform(360)
    saturation = :rand.uniform() * 25 + 60
    lightness = :rand.uniform() * 25 + 45
    hsl = Chameleon.HSL.new(trunc(hue), trunc(saturation), trunc(lightness))
    %Chameleon.RGB{r: r, g: g, b: b} = Chameleon.convert(hsl, Chameleon.RGB)

    sim =
      if cell_empty?(sim, sim.spawn_pos) do
        put_cell(sim, sim.spawn_pos, {:sand, {r, g, b}})
      else
        sim
      end

    min_x = Enum.map(sim.particles, fn {{x, _}, _} -> x end) |> Enum.min()
    max_x = Enum.map(sim.particles, fn {{x, _}, _} -> x end) |> Enum.max()
    min_y = Enum.map(sim.particles, fn {{_, y}, _} -> y end) |> Enum.min()
    max_y = Enum.map(sim.particles, fn {{_, y}, _} -> y end) |> Enum.max()

    sim =
      for y <- min_y..max_y,
          x <- min_x..max_x,
          cell = get_cell(sim, {x, y}),
          cell != nil,
          reduce: sim do
        sim ->
          below = {x, y + 1}
          below_left = {x - 1, y + 1}
          below_right = {x + 1, y + 1}

          cond do
            cell_empty?(sim, below) ->
              sim
              |> remove_cell({x, y})
              |> put_cell(below, cell)

            cell_empty?(sim, below_left) ->
              sim
              |> remove_cell({x, y})
              |> put_cell(below_left, cell)

            cell_empty?(sim, below_right) ->
              sim
              |> remove_cell({x, y})
              |> put_cell(below_right, cell)

            true ->
              sim
          end
      end

    {spawn_pos, spawn_pos_dir} =
      case sim.spawn_pos do
        {x, y} when x + sim.spawn_pos_dir < 0 or x + sim.spawn_pos_dir >= sim.width ->
          {{x, y}, -sim.spawn_pos_dir}

        {x, y} ->
          {{x + sim.spawn_pos_dir, y}, sim.spawn_pos_dir}
      end

    dbg(spawn_pos)

    %Sim{sim | spawn_pos: sim.spawn_pos, spawn_pos_dir: spawn_pos_dir}
  end

  def draw(%Sim{} = sim, canvas) do
    for y <- 0..(canvas.height - 1),
        x <- 0..(canvas.width - 1),
        into: canvas do
      case get_cell(sim, {x, y}) do
        {:sand, color} -> {{x, y}, color}
        _ -> {{x, y}, {0, 0, 0}}
      end
    end
  end

  defp cell_empty?(sim, {x, y}) do
    if x < 0 or x >= sim.width or y >= sim.height do
      false
    else
      !Map.has_key?(sim.particles, {x, y})
    end
  end

  defp get_cell(sim, {x, y}, default \\ nil) do
    Map.get(sim.particles, {x, y}, default)
  end

  defp put_cell(sim, {x, y}, value) do
    %Sim{sim | particles: Map.put(sim.particles, {x, y}, value)}
  end

  defp remove_cell(sim, {x, y}) do
    %Sim{sim | particles: Map.delete(sim.particles, {x, y})}
  end
end
