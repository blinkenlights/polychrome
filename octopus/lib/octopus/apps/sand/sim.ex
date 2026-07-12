defmodule Octopus.Apps.Sand.Sim do
  @enforce_keys [
    :width,
    :height,
    :led_width,
    :led_height,
    :supersample,
    :gravity,
    :v_max,
    :panel_led_ranges,
    :particles
  ]
  defstruct [
    :width,
    :height,
    :led_width,
    :led_height,
    :supersample,
    :gravity,
    :v_max,
    :panel_led_ranges,
    :particles
  ]

  alias __MODULE__
  alias Octopus.Canvas

  @type particle() :: {:sand, Canvas.color(), float(), float()}
  @type coord() :: {integer(), integer()}
  @type event() :: {:abyss, coord(), particle()} | {:plug_drain, coord(), particle()}
  @type ctx() :: %{
          optional(:wind_strength) => float(),
          optional(:color_mix) => float(),
          optional(:overflow_mode) => :block | :waterfall | :abyss,
          optional(:plug_x) => integer() | nil,
          optional(:plug_width) => pos_integer(),
          optional(:plug_active) => boolean()
        }

  @type t() :: %__MODULE__{
          width: integer(),
          height: integer(),
          led_width: integer(),
          led_height: integer(),
          supersample: pos_integer(),
          gravity: float(),
          v_max: float(),
          panel_led_ranges: [{integer(), integer()}],
          particles: %{required(coord()) => particle()}
        }

  @spec sand(Canvas.color(), float(), float()) :: particle()
  def sand(color, vy \\ 0.0, vx \\ 0.0), do: {:sand, color, vy, vx}

  @spec normalize_particle(term()) :: particle()
  def normalize_particle({:sand, color}), do: {:sand, color, 0.0, 0.0}
  def normalize_particle({:sand, color, vy}), do: {:sand, color, vy, 0.0}
  def normalize_particle({:sand, color, vy, vx}), do: {:sand, color, vy, vx}

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
      panel_led_ranges: Keyword.get(opts, :panel_led_ranges, []),
      particles: %{}
    }
  end

  @spec step(t(), ctx()) :: {t(), [event()]}
  def step(%Sim{} = sim, ctx \\ %{}) do
    if map_size(sim.particles) == 0 do
      {sim, []}
    else
      ctx = normalize_ctx(ctx)
      side_order = base_side_order(ctx.wind_strength)

      {sim, events} =
        sim.particles
        |> Map.keys()
        |> Enum.sort_by(fn {x, y} -> {-y, x} end)
        |> Enum.reduce({sim, []}, fn coord, {sim, events} ->
          case move_grain(sim, coord, side_order, ctx) do
            {sim, nil} -> {sim, events}
            {sim, event} -> {sim, [event | events]}
          end
        end)

      {sim, Enum.reverse(events)}
    end
  end

  defp normalize_ctx(ctx) when is_map(ctx) do
    %{
      wind_strength: Map.get(ctx, :wind_strength, 0.0) * 1.0,
      color_mix: clamp01(Map.get(ctx, :color_mix, 0.0)),
      overflow_mode: Map.get(ctx, :overflow_mode, :block),
      plug_x: Map.get(ctx, :plug_x),
      plug_width: max(Map.get(ctx, :plug_width, 1), 1),
      plug_active: Map.get(ctx, :plug_active, false) == true
    }
  end

  defp move_grain(%Sim{} = sim, coord, side_order, ctx) do
    case get_cell(sim, coord) do
      nil ->
        {sim, nil}

      particle ->
        {:sand, color, vy, vx} = normalize_particle(particle)
        {sim, coord, _particle, event} = maybe_plug_drain(sim, coord, particle, ctx)

        if event do
          {sim, event}
        else
          side_order = plug_side_order(side_order, coord, sim, ctx)
          vy = min(vy + sim.gravity, sim.v_max)
          particle = {:sand, color, vy, vx}

          {sim, coord, particle} = maybe_drift_horizontal(sim, coord, particle, ctx)

          max_steps = max(trunc(vy), 1)
          {sim, {fx, fy}, fallen, abyss_event} = fall_down(sim, coord, particle, max_steps, ctx)

          cond do
            abyss_event ->
              {sim, {:abyss, elem(abyss_event, 1), elem(abyss_event, 2)}}

            true ->
              sim =
                cond do
                  fallen == 0 ->
                    case try_slide(sim, coord, {:sand, color, 1.0, 0.0}, side_order, ctx) do
                      {:moved, sim} -> sim
                      {:blocked, sim} -> put_cell(sim, coord, sand(color, 1.0, 0.0), ctx)
                    end

                  fallen > 0 and fallen < max_steps ->
                    put_cell(sim, {fx, fy}, sand(color, 1.0, 0.0), ctx)

                  fallen == max_steps and not cell_empty?(sim, {fx, fy + 1}, ctx) ->
                    put_cell(sim, {fx, fy}, sand(color, 1.0, 0.0), ctx)

                  true ->
                    sim
                end

              {sim, nil}
          end
        end
    end
  end

  defp maybe_plug_drain(sim, {x, y} = coord, particle, ctx) do
    if ctx.plug_active and ctx.plug_x != nil and in_plug_column?(sim, x, ctx) and
         at_bottom_row?(sim, y) do
      {remove_cell(sim, coord), coord, particle, {:plug_drain, coord, particle}}
    else
      {sim, coord, particle, nil}
    end
  end

  defp maybe_drift_horizontal(sim, {x, y} = coord, {:sand, _color, _vy, vx} = particle, ctx) do
    wind = ctx.wind_strength
    drift = if abs(vx) > 0.01, do: vx, else: wind * 0.15
    target = {x + sign(drift), y}

    if abs(drift) > 0.01 and cell_empty?(sim, target, ctx) do
      {sim |> remove_cell(coord) |> put_cell(target, particle, ctx), target, particle}
    else
      {sim, coord, particle}
    end
  end

  defp fall_down(sim, {x, y} = coord, particle, max_steps, ctx, fallen \\ 0) do
    below = {x, y + 1}

    cond do
      fallen < max_steps and cell_empty?(sim, below, ctx) ->
        sim = sim |> remove_cell(coord) |> put_cell(below, particle, ctx)
        fall_down(sim, below, particle, max_steps, ctx, fallen + 1)

      ctx.overflow_mode == :abyss and abyss_below?(sim, below) ->
        {remove_cell(sim, coord), {x, y}, fallen, {:abyss, coord, particle}}

      true ->
        {sim, {x, y}, fallen, nil}
    end
  end

  defp try_slide(sim, {x, y} = coord, particle, side_order, ctx) do
    diagonals =
      Enum.map(side_order, fn
        :left -> {x - 1, y + 1}
        :right -> {x + 1, y + 1}
      end)

    targets = diagonals ++ waterfall_targets(sim, {x, y}, side_order, ctx)

    case Enum.find_value(targets, fn target ->
           if cell_empty?(sim, target, ctx), do: target
         end) do
      nil ->
        {:blocked, sim}

      target ->
        {:moved, sim |> remove_cell(coord) |> put_cell(target, particle, ctx)}
    end
  end

  defp waterfall_targets(sim, {x, y}, side_order, %{overflow_mode: :waterfall}) do
    s = sim.supersample
    led_x = div(x, s)
    led_y = div(y, s)

    Enum.flat_map(side_order, fn side ->
      case panel_neighbor(sim, led_x, side) do
        nil -> []
        neighbor_start -> [{neighbor_start * s, y + 1}]
      end
    end)
    |> Enum.filter(fn _target ->
      led_y >= 0 and led_y < sim.led_height
    end)
  end

  defp waterfall_targets(_sim, _coord, _side_order, _ctx), do: []

  defp panel_neighbor(%Sim{panel_led_ranges: ranges}, led_x, :right) do
    case Enum.find_index(ranges, fn {start_x, end_x} -> led_x >= start_x and led_x <= end_x end) do
      nil ->
        nil

      idx ->
        case Enum.at(ranges, idx + 1) do
          {start_x, _end_x} -> start_x
          _ -> nil
        end
    end
  end

  defp panel_neighbor(%Sim{panel_led_ranges: ranges}, led_x, :left) do
    case Enum.find_index(ranges, fn {start_x, end_x} -> led_x >= start_x and led_x <= end_x end) do
      nil ->
        nil

      0 ->
        nil

      idx ->
        case Enum.at(ranges, idx - 1) do
          {_start_x, end_x} -> end_x
          _ -> nil
        end
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
            {:sand, {r, g, b}, _, _} -> {sr + r, sg + g, sb + b}
            {:sand, {r, g, b}, _} -> {sr + r, sg + g, sb + b}
            {:sand, {r, g, b}} -> {sr + r, sg + g, sb + b}
            _ -> {sr, sg, sb}
          end
      end

    {div(sum_r, s2), div(sum_g, s2), div(sum_b, s2)}
  end

  @spec cell_empty?(t(), coord(), ctx()) :: boolean()
  def cell_empty?(%Sim{} = sim, {x, y}, ctx \\ %{}) do
    ctx = normalize_ctx(ctx)

    cond do
      y >= sim.height ->
        ctx.overflow_mode == :abyss

      y < 0 ->
        true

      gap_cell?(sim, x, y) ->
        ctx.overflow_mode in [:waterfall, :abyss]

      true ->
        !Map.has_key?(sim.particles, normalize_coord(sim, {x, y}))
    end
  end

  defp gap_cell?(%Sim{} = sim, x, y) do
    sim.panel_led_ranges != [] and
      not led_on_panel?(sim, div(x, sim.supersample), div(y, sim.supersample))
  end

  defp abyss_below?(sim, {x, y}) do
    y >= sim.height or gap_cell?(sim, x, y)
  end

  defp led_on_panel?(%Sim{} = sim, led_x, led_y) do
    led_y >= 0 and led_y < sim.led_height and
      Enum.any?(sim.panel_led_ranges, fn {start_x, end_x} ->
        led_x >= start_x and led_x <= end_x
      end)
  end

  @spec get_cell(t(), coord(), particle() | nil) :: particle() | nil
  def get_cell(%Sim{} = sim, {x, y}, default \\ nil) do
    Map.get(sim.particles, normalize_coord(sim, {x, y}), default)
  end

  @spec put_cell(t(), coord(), term(), ctx()) :: t()
  def put_cell(%Sim{} = sim, {x, y}, value, ctx \\ %{}) do
    ctx = normalize_ctx(ctx)

    cond do
      gap_cell?(sim, x, y) and ctx.overflow_mode == :block ->
        sim

      gap_cell?(sim, x, y) and ctx.overflow_mode == :abyss ->
        sim

      true ->
        coord = normalize_coord(sim, {x, y})
        particle = normalize_particle(value)
        particle = mix_with_neighbors(sim, coord, particle, ctx)
        %Sim{sim | particles: Map.put(sim.particles, coord, particle)}
    end
  end

  defp mix_with_neighbors(sim, {x, y}, {:sand, color, vy, vx} = particle, ctx) do
    if ctx.color_mix <= 0 do
      particle
    else
      neighbors =
        [{x - 1, y}, {x + 1, y}, {x, y - 1}]
        |> Enum.map(&get_cell(sim, &1))
        |> Enum.reject(&is_nil/1)
        |> Enum.map(fn {:sand, c, _, _} -> c end)

      case neighbors do
        [] ->
          particle

        neighbor_colors ->
          mixed =
            Enum.reduce(neighbor_colors, color, fn nc, acc ->
              lerp_rgb(acc, nc, ctx.color_mix)
            end)

          {:sand, mixed, vy, vx}
      end
    end
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

  @spec column_heights(t()) :: %{integer() => integer()}
  def column_heights(%Sim{} = sim) do
    sim.particles
    |> Map.keys()
    |> Enum.reduce(%{}, fn {x, y}, acc ->
      Map.update(acc, x, y, &min(&1, y))
    end)
  end

  @spec trigger_collapse(t(), [integer()]) :: t()
  def trigger_collapse(%Sim{} = sim, columns) when is_list(columns) do
    column_set = MapSet.new(columns)

    particles =
      Map.new(sim.particles, fn {coord, particle} ->
        {x, _y} = coord

        if MapSet.member?(column_set, x) do
          {:sand, color, _vy, vx} = normalize_particle(particle)
          {coord, {:sand, color, sim.v_max, vx}}
        else
          {coord, particle}
        end
      end)

    %Sim{sim | particles: particles}
  end

  defp normalize_coord(%Sim{} = sim, {x, y}) do
    {Integer.mod(x, sim.width), y}
  end

  defp base_side_order(wind) when wind > 0.15, do: [:right, :left]
  defp base_side_order(wind) when wind < -0.15, do: [:left, :right]
  defp base_side_order(_wind), do: if(:rand.uniform() > 0.5, do: [:left, :right], else: [:right, :left])

  defp plug_side_order(side_order, {x, _y}, sim, ctx) do
    if ctx.plug_active and ctx.plug_x != nil and near_plug?(sim, x, ctx) do
      plug_sim_x = ctx.plug_x * sim.supersample

      if x < plug_sim_x do
        [:right, :left]
      else
        [:left, :right]
      end
    else
      side_order
    end
  end

  defp in_plug_column?(sim, x, ctx) do
    near_plug?(sim, x, ctx)
  end

  defp near_plug?(sim, x, ctx) do
    plug_sim_x = ctx.plug_x * sim.supersample
    half = div(ctx.plug_width * sim.supersample, 2)
    abs(x - plug_sim_x) <= half
  end

  defp at_bottom_row?(sim, y) do
    y >= sim.height - 1
  end

  defp lerp_rgb({r1, g1, b1}, {r2, g2, b2}, t) do
    t = clamp01(t)

    {
      trunc(r1 + (r2 - r1) * t),
      trunc(g1 + (g2 - g1) * t),
      trunc(b1 + (b2 - b1) * t)
    }
  end

  defp clamp01(v) when is_number(v), do: v |> max(0.0) |> min(1.0)

  defp sign(v) when v > 0, do: 1
  defp sign(v) when v < 0, do: -1
  defp sign(_), do: 0
end
