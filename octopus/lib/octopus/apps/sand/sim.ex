defmodule Octopus.Apps.Sand.Sim do
  @enforce_keys [:width, :height, :particles]
  defstruct [:width, :height, :particles]

  alias __MODULE__
  alias Octopus.Canvas

  @type particle() :: {:sand, Canvas.color()}

  @type coord() :: {integer(), integer()}

  @type t() :: %__MODULE__{
          width: integer(),
          height: integer(),
          particles: %{required(coord()) => particle()}
        }

  @spec new(integer(), integer()) :: t()
  def new(width, height) do
    %Sim{
      width: width,
      height: height,
      particles: %{}
    }
  end

  @spec step(t()) :: t()
  def step(%Sim{} = sim) do
    if map_size(sim.particles) == 0 do
      sim
    else
      min_x = Enum.map(sim.particles, fn {{x, _}, _} -> x end) |> Enum.min()
      max_x = Enum.map(sim.particles, fn {{x, _}, _} -> x end) |> Enum.max()
      min_y = Enum.map(sim.particles, fn {{_, y}, _} -> y end) |> Enum.min()
      max_y = Enum.map(sim.particles, fn {{_, y}, _} -> y end) |> Enum.max()

      for y <- min_y..max_y,
          x <- min_x..max_x,
          cell = get_cell(sim, {x, y}),
          cell != nil,
          reduce: sim do
        sim ->
          below = {x, y + 1}

          {below_side_1, below_side_2} =
            if :rand.uniform() > 0.5 do
              {{x - 1, y + 1}, {x + 1, y + 1}}
            else
              {{x + 1, y + 1}, {x - 1, y + 1}}
            end

          cond do
            cell_empty?(sim, below) ->
              sim
              |> remove_cell({x, y})
              |> put_cell(below, cell)

            cell_empty?(sim, below_side_1) ->
              sim
              |> remove_cell({x, y})
              |> put_cell(below_side_1, cell)

            cell_empty?(sim, below_side_2) ->
              sim
              |> remove_cell({x, y})
              |> put_cell(below_side_2, cell)

            true ->
              sim
          end
      end
    end
  end

  @spec clear(t()) :: t()
  def clear(%Sim{} = sim) do
    %Sim{sim | particles: %{}}
  end

  @spec draw(t(), Canvas.t()) :: Canvas.t()
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

  @spec cell_empty?(t(), coord()) :: boolean()
  def cell_empty?(%Sim{} = sim, {x, y}) do
    if x < 0 or x >= sim.width or y >= sim.height do
      false
    else
      !Map.has_key?(sim.particles, {x, y})
    end
  end

  @spec get_cell(t(), coord(), particle()) :: particle() | nil
  def get_cell(%Sim{} = sim, {x, y}, default \\ nil) do
    Map.get(sim.particles, {x, y}, default)
  end

  @spec put_cell(t(), coord(), particle()) :: t()
  def put_cell(%Sim{} = sim, {x, y}, value) do
    %Sim{sim | particles: Map.put(sim.particles, {x, y}, value)}
  end

  @spec remove_cell(t(), coord()) :: t()
  def remove_cell(%Sim{} = sim, {x, y}) do
    %Sim{sim | particles: Map.delete(sim.particles, {x, y})}
  end
end
