defmodule Octopus.Apps.Sand.Sim do
  @enforce_keys [:width, :height, :led_width, :led_height, :supersample, :gravity, :v_max, :particles]
  defstruct [:width, :height, :led_width, :led_height, :supersample, :gravity, :v_max, :particles]

  alias __MODULE__
  alias Octopus.Canvas

  @type particle() :: {:sand, Canvas.color(), float()}

  @type coord() :: {integer(), integer()}

  @type t() :: %__MODULE__{
          width: integer(),
          height: integer(),
          led_width: integer(),
          led_height: integer(),
          supersample: pos_integer(),
          gravity: float(),
          v_max: float(),
          particles: %{required(coord()) => particle()}
        }

  @spec sand(Canvas.color(), float()) :: particle()
  def sand(color, vy \\ 0.0), do: {:sand, color, vy}

  @spec normalize_particle({:sand, Canvas.color()} | particle()) :: particle()
  def normalize_particle({:sand, color}), do: {:sand, color, 0.0}
  def normalize_particle({:sand, color, vy}), do: {:sand, color, vy}

  @spec default_gravity(pos_integer()) :: float()
  def default_gravity(s), do: 0.35 * s / 4

  @spec default_v_max(pos_integer()) :: float()
  def default_v_max(s), do: 2.0 * s

  @spec new(integer(), integer(), keyword()) :: t()
  def new(led_width, led_height, opts \\ []) do
    s = Keyword.get(opts, :supersample, 1)
    gravity = Keyword.get(opts, :gravity, default_gravity(s))

    %Sim{
      width: led_width * s,
      height: led_height * s,
      led_width: led_width,
      led_height: led_height,
      supersample: s,
      gravity: gravity,
      v_max: default_v_max(s),
      particles: %{}
    }
  end

  @spec step(t()) :: t()
  def step(%Sim{} = sim) do
    if map_size(sim.particles) == 0 do
      sim
    else
      side_order = if :rand.uniform() > 0.5, do: [:left, :right], else: [:right, :left]

      sim.particles
      |> Map.keys()
      |> Enum.sort_by(fn {x, y} -> {-y, x} end)
      |> Enum.reduce(sim, &move_grain(&2, &1, side_order))
    end
  end

  defp move_grain(%Sim{} = sim, coord, side_order) do
    case get_cell(sim, coord) do
      nil ->
        sim

      particle ->
        {:sand, color, vy} = normalize_particle(particle)
        vy = min(vy + sim.gravity, sim.v_max)
        particle = {:sand, color, vy}
        max_steps = max(trunc(vy), 1)

        {sim, {fx, fy}, fallen} = fall_down(sim, coord, particle, max_steps)

        cond do
          fallen == 0 ->
            case try_diagonal_move(sim, coord, {:sand, color, 1.0}, side_order) do
              {:moved, sim} -> sim
              {:blocked, sim} -> put_cell(sim, coord, sand(color, 1.0))
            end

          fallen > 0 and fallen < max_steps ->
            put_cell(sim, {fx, fy}, sand(color, 1.0))

          fallen == max_steps and not cell_empty?(sim, {fx, fy + 1}) ->
            put_cell(sim, {fx, fy}, sand(color, 1.0))

          true ->
            sim
        end
    end
  end

  defp fall_down(sim, {x, y} = coord, particle, max_steps, fallen \\ 0) do
    below = {x, y + 1}

    if fallen < max_steps and cell_empty?(sim, below) do
      sim = sim |> remove_cell(coord) |> put_cell(below, particle)
      fall_down(sim, below, particle, max_steps, fallen + 1)
    else
      {sim, {x, y}, fallen}
    end
  end

  defp try_diagonal_move(sim, {x, y}, particle, side_order) do
    diagonals =
      Enum.map(side_order, fn
        :left -> {x - 1, y + 1}
        :right -> {x + 1, y + 1}
      end)

    case Enum.find(diagonals, &cell_empty?(sim, &1)) do
      nil ->
        {:blocked, sim}

      diag ->
        sim = sim |> remove_cell({x, y}) |> put_cell(diag, particle)
        {:moved, sim}
    end
  end

  @spec clear(t()) :: t()
  def clear(%Sim{} = sim) do
    %Sim{sim | particles: %{}}
  end

  @spec draw(t(), Canvas.t()) :: Canvas.t()
  def draw(%Sim{} = sim, canvas) do
    s = sim.supersample
    s2 = s * s

    for ly <- 0..(sim.led_height - 1),
        lx <- 0..(sim.led_width - 1),
        into: canvas do
      color = average_block(sim, lx, ly, s, s2)
      {{lx, ly}, color}
    end
  end

  defp average_block(sim, lx, ly, s, s2) do
    base_x = lx * s
    base_y = ly * s

    {sum_r, sum_g, sum_b} =
      for dy <- 0..(s - 1),
          dx <- 0..(s - 1),
          reduce: {0, 0, 0} do
        {sr, sg, sb} ->
          case Map.get(sim.particles, {base_x + dx, base_y + dy}) do
            {:sand, {r, g, b}, _} -> {sr + r, sg + g, sb + b}
            {:sand, {r, g, b}} -> {sr + r, sg + g, sb + b}
            _ -> {sr, sg, sb}
          end
      end

    {div(sum_r, s2), div(sum_g, s2), div(sum_b, s2)}
  end

  @spec cell_empty?(t(), coord()) :: boolean()
  def cell_empty?(%Sim{} = sim, {x, y}) do
    cond do
      y >= sim.height -> false
      y < 0 -> true
      true -> !Map.has_key?(sim.particles, normalize_coord(sim, {x, y}))
    end
  end

  @spec get_cell(t(), coord(), particle() | nil) :: particle() | nil
  def get_cell(%Sim{} = sim, {x, y}, default \\ nil) do
    Map.get(sim.particles, normalize_coord(sim, {x, y}), default)
  end

  @spec put_cell(t(), coord(), {:sand, Canvas.color()} | particle()) :: t()
  def put_cell(%Sim{} = sim, {x, y}, value) do
    coord = normalize_coord(sim, {x, y})
    %Sim{sim | particles: Map.put(sim.particles, coord, normalize_particle(value))}
  end

  @spec remove_cell(t(), coord()) :: t()
  def remove_cell(%Sim{} = sim, {x, y}) do
    coord = normalize_coord(sim, {x, y})
    %Sim{sim | particles: Map.delete(sim.particles, coord)}
  end

  @spec with_gravity(t(), float()) :: t()
  def with_gravity(%Sim{} = sim, gravity) do
    %Sim{sim | gravity: gravity}
  end

  defp normalize_coord(%Sim{} = sim, {x, y}) do
    {Integer.mod(x, sim.width), y}
  end
end
