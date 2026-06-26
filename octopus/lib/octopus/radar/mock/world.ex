defmodule Octopus.Radar.Mock.World do
  @moduledoc """
  Shared virtual world for radar mock mode.

  Simulates people loitering on a circular ground (a disk centered on the
  installation center, default radius 10 m). All positions are expressed in
  the same global meters frame as the sensor poses and the post-`Transform`
  detections, so the live view can render everything on one canvas.

  This GenServer is the single source of truth that every per-sensor mock
  device (`Octopus.Radar.Mock.Server`) reads from via `objects/0`. Because
  all mock sensors derive their detections from the *same* objects, the
  cross-sensor coordinate-agreement property becomes meaningful: in `:exact`
  mode every sensor that sees a given person reports the same global position.

  ## People behavior

  Each person runs a small state machine:

    * `:standing` — stands still for a few seconds
    * `:wander_slow` — strolls at ~0.2-0.5 m/s toward a random point
    * `:wander_fast` — walks at ~0.8-1.4 m/s toward a random point

  The live population is kept within `1..max_people`; people appear and
  disappear over time. `max_people` is operator-adjustable at runtime.

  ## Ground-truth feed

  On every tick the current snapshot is broadcast as `{:mock_world, objects}`
  on `"#{Octopus.Radar.topic()}:world"` so the UI can draw true positions.
  """

  use GenServer

  alias Octopus.Radar

  @tick_ms 100
  @default_radius_m 8.0
  @default_max_people 5
  @default_entropy 50
  @edge_margin_m 0.5

  # Behavior parameter ranges. The standing/slow/fast mix and dwell times are
  # modulated at runtime by the activity "entropy" (see `pick_behavior/4`).
  @slow_speed {0.2, 0.5}
  @fast_speed {0.8, 1.4}
  @stand_ms {2_000, 6_000}
  @wander_ms {2_000, 5_000}
  @z_range {1.6, 1.85}

  # Per-tick spawn/despawn probabilities (10 Hz tick → these are per 100 ms).
  @spawn_prob 0.05
  @despawn_prob 0.01

  ## Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Current ground-truth objects as a list of `%{id, x, y, z, vx, vy}` (global meters)."
  @spec objects() :: [map()]
  def objects, do: GenServer.call(__MODULE__, :objects)

  @doc "World radius in meters."
  @spec radius_m() :: float()
  def radius_m, do: GenServer.call(__MODULE__, :radius_m)

  @doc "Current simulation mode (`:off`, `:exact`, `:fuzzy`)."
  @spec mode() :: :off | :exact | :fuzzy
  def mode, do: GenServer.call(__MODULE__, :mode)

  @doc "Set the simulation mode. `:off` clears all people."
  @spec set_mode(:off | :exact | :fuzzy) :: :ok
  def set_mode(mode) when mode in [:off, :exact, :fuzzy],
    do: GenServer.call(__MODULE__, {:set_mode, mode})

  @doc "Current population cap (1..10)."
  @spec max_people() :: pos_integer()
  def max_people, do: GenServer.call(__MODULE__, :max_people)

  @doc "Set the population cap (clamped to 1..10)."
  @spec set_max_people(integer()) :: :ok
  def set_max_people(n) when is_integer(n), do: GenServer.call(__MODULE__, {:set_max_people, n})

  @doc "Current activity level (\"entropy\"), 0..100."
  @spec entropy() :: 0..100
  def entropy, do: GenServer.call(__MODULE__, :entropy)

  @doc """
  Set the activity level (0..100). Higher values make people wander more
  often, faster, and stand still for shorter periods; lower values make them
  mostly stand around.
  """
  @spec set_entropy(integer()) :: :ok
  def set_entropy(n) when is_integer(n), do: GenServer.call(__MODULE__, {:set_entropy, n})

  @doc """
  Test seam: replace the live population with a fixed object set and freeze
  motion so positions stay put across ticks. Each object is a map with at
  least `:id`, `:x`, `:y`; `:z`, `:vx`, `:vy` default to sensible values.
  """
  @spec set_objects([map()]) :: :ok
  def set_objects(objects) when is_list(objects),
    do: GenServer.call(__MODULE__, {:set_objects, objects})

  ## GenServer callbacks

  @impl true
  def init(opts) do
    radius_m = Keyword.get(opts, :radius_m, configured_radius_m())
    max_people = Keyword.get(opts, :max_people, @default_max_people) |> clamp_max_people()

    state = %{
      radius_m: radius_m,
      mode: Keyword.get(opts, :mode, :off),
      max_people: max_people,
      entropy: Keyword.get(opts, :entropy, @default_entropy) |> clamp_entropy(),
      people: [],
      next_id: 1,
      frozen: false
    }

    Process.send_after(self(), :tick, @tick_ms)
    {:ok, state}
  end

  @impl true
  def handle_call(:objects, _from, state), do: {:reply, public_objects(state.people), state}

  def handle_call(:radius_m, _from, state), do: {:reply, state.radius_m, state}

  def handle_call(:mode, _from, state), do: {:reply, state.mode, state}

  def handle_call(:max_people, _from, state), do: {:reply, state.max_people, state}

  def handle_call({:set_mode, mode}, _from, state) do
    state =
      case mode do
        :off -> %{state | mode: :off, people: []}
        _ -> %{state | mode: mode, frozen: false}
      end

    {:reply, :ok, state}
  end

  def handle_call({:set_max_people, n}, _from, state) do
    {:reply, :ok, %{state | max_people: clamp_max_people(n)}}
  end

  def handle_call(:entropy, _from, state), do: {:reply, state.entropy, state}

  def handle_call({:set_entropy, n}, _from, state) do
    {:reply, :ok, %{state | entropy: clamp_entropy(n)}}
  end

  def handle_call({:set_objects, objects}, _from, state) do
    now = System.monotonic_time(:millisecond)

    people =
      Enum.map(objects, fn obj ->
        %{
          id: Map.fetch!(obj, :id),
          x: Map.fetch!(obj, :x),
          y: Map.fetch!(obj, :y),
          z: Map.get(obj, :z, 1.7),
          vx: Map.get(obj, :vx, 0.0),
          vy: Map.get(obj, :vy, 0.0),
          behavior: :standing,
          target_x: Map.fetch!(obj, :x),
          target_y: Map.fetch!(obj, :y),
          speed: 0.0,
          until_ms: now + 1_000_000
        }
      end)

    next_id =
      case people do
        [] -> state.next_id
        _ -> (people |> Enum.map(& &1.id) |> Enum.max()) + 1
      end

    {:reply, :ok, %{state | people: people, frozen: true, next_id: next_id}}
  end

  @impl true
  def handle_info(:tick, state) do
    Process.send_after(self(), :tick, @tick_ms)
    state = step(state)
    broadcast(state)
    {:noreply, state}
  end

  ## Simulation

  defp step(%{mode: :off} = state), do: state
  defp step(%{frozen: true} = state), do: state

  defp step(state) do
    now = System.monotonic_time(:millisecond)
    dt = @tick_ms / 1000.0
    factor = state.entropy / 100.0

    people =
      state.people
      |> Enum.map(&update_person(&1, now, dt, state.radius_m, factor))

    {people, next_id} =
      manage_population(people, state.max_people, state.radius_m, now, state.next_id, factor)

    %{state | people: people, next_id: next_id}
  end

  defp update_person(person, now, dt, radius, factor) do
    person = if now >= person.until_ms, do: retarget(person, now, radius, factor), else: person

    dx = person.target_x - person.x
    dy = person.target_y - person.y
    dist = :math.sqrt(dx * dx + dy * dy)

    {x, y, vx, vy} =
      if person.speed > 0.0 and dist > 0.05 do
        ux = dx / dist
        uy = dy / dist
        vx = ux * person.speed
        vy = uy * person.speed
        {person.x + vx * dt, person.y + vy * dt, vx, vy}
      else
        {person.x, person.y, 0.0, 0.0}
      end

    {x, y, vx, vy, target_x, target_y} =
      clamp_to_disk(x, y, vx, vy, person.target_x, person.target_y, radius)

    %{person | x: x, y: y, vx: vx, vy: vy, target_x: target_x, target_y: target_y}
  end

  # Keep people inside the disk: if a step would carry them past the usable
  # edge, pin to the boundary and aim the next target back toward the center.
  defp clamp_to_disk(x, y, vx, vy, target_x, target_y, radius) do
    usable = radius - @edge_margin_m
    dist = :math.sqrt(x * x + y * y)

    if dist > usable and dist > 0.0 do
      scale = usable / dist
      {x * scale, y * scale, 0.0, 0.0, x * scale * 0.2, y * scale * 0.2}
    else
      {x, y, vx, vy, target_x, target_y}
    end
  end

  defp retarget(person, now, radius, factor) do
    case pick_behavior(:rand.uniform(), factor) do
      :standing ->
        # Higher entropy → shorter dwell before moving again.
        dwell = round(rand_in(@stand_ms) * (1.0 - 0.6 * factor))

        %{
          person
          | behavior: :standing,
            speed: 0.0,
            target_x: person.x,
            target_y: person.y,
            until_ms: now + max(dwell, 400)
        }

      :wander_slow ->
        start_wander(person, :wander_slow, @slow_speed, now, radius, factor)

      :wander_fast ->
        start_wander(person, :wander_fast, @fast_speed, now, radius, factor)
    end
  end

  # Choose the next behavior given a uniform roll and the activity factor
  # (0..1). Low factor → mostly standing and, when moving, slow; high factor →
  # rarely standing and, when moving, often fast.
  defp pick_behavior(roll, factor) do
    p_stand = clampf(0.7 - 0.6 * factor, 0.05, 0.9)

    cond do
      roll < p_stand -> :standing
      :rand.uniform() < factor -> :wander_fast
      true -> :wander_slow
    end
  end

  defp start_wander(person, behavior, speed_range, now, radius, factor) do
    {tx, ty} = random_point_in_disk(radius - @edge_margin_m)

    %{
      person
      | behavior: behavior,
        speed: rand_in(speed_range) * (0.5 + 0.5 * factor),
        target_x: tx,
        target_y: ty,
        until_ms: now + rand_in(@wander_ms)
    }
  end

  defp manage_population(people, max_people, radius, now, next_id, factor) do
    count = length(people)

    cond do
      count > max_people ->
        {Enum.take_random(people, max_people), next_id}

      count == 0 ->
        {[spawn_person(radius, now, next_id, factor)], next_id + 1}

      count < max_people and :rand.uniform() < @spawn_prob ->
        {[spawn_person(radius, now, next_id, factor) | people], next_id + 1}

      count > 1 and :rand.uniform() < @despawn_prob ->
        {Enum.drop(Enum.shuffle(people), 1), next_id}

      true ->
        {people, next_id}
    end
  end

  # People enter from the world border and then head inward, rather than
  # popping into existence in the middle of the scene.
  defp spawn_person(radius, now, id, factor) do
    usable = radius - @edge_margin_m
    theta = 2.0 * :math.pi() * :rand.uniform()
    x = usable * :math.cos(theta)
    y = usable * :math.sin(theta)

    {tx, ty} = random_point_in_disk(usable * 0.7)
    behavior = if :rand.uniform() < factor, do: :wander_fast, else: :wander_slow
    speed_range = if behavior == :wander_fast, do: @fast_speed, else: @slow_speed

    %{
      id: id,
      x: x,
      y: y,
      z: rand_in(@z_range),
      vx: 0.0,
      vy: 0.0,
      behavior: behavior,
      target_x: tx,
      target_y: ty,
      speed: rand_in(speed_range) * (0.5 + 0.5 * factor),
      until_ms: now + rand_in(@wander_ms)
    }
  end

  defp random_point_in_disk(radius) do
    theta = 2.0 * :math.pi() * :rand.uniform()
    r = radius * :math.sqrt(:rand.uniform())
    {r * :math.cos(theta), r * :math.sin(theta)}
  end

  defp rand_in({lo, hi}) when is_integer(lo) and is_integer(hi),
    do: lo + :rand.uniform(hi - lo + 1) - 1

  defp rand_in({lo, hi}), do: lo + :rand.uniform() * (hi - lo)

  defp public_objects(people) do
    Enum.map(people, fn p ->
      %{id: p.id, x: p.x, y: p.y, z: p.z, vx: p.vx, vy: p.vy}
    end)
  end

  defp broadcast(state) do
    Phoenix.PubSub.broadcast(
      Octopus.PubSub,
      world_topic(),
      {:mock_world, public_objects(state.people)}
    )
  end

  @doc "PubSub topic carrying ground-truth world snapshots."
  @spec world_topic() :: String.t()
  def world_topic, do: "#{Radar.topic()}:world"

  defp clamp_max_people(n), do: n |> max(1) |> min(10)

  defp clamp_entropy(n), do: n |> max(0) |> min(100)

  defp clampf(v, lo, hi), do: v |> max(lo) |> min(hi)

  defp configured_radius_m do
    Application.get_env(:octopus, Octopus.Radar, [])
    |> Keyword.get(:mock, [])
    |> Keyword.get(:radius_m, @default_radius_m)
  end
end
