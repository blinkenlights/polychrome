defmodule Octopus.Apps.Collective.MockCrowd do
  @moduledoc """
  Self-contained mock of people around the installation ring.

  Each person mirrors `Octopus.Radar.Track` fields (`x`, `y`, `vx`, `vy` in m / m/s).

  Behaviour:

    * **Dynamic population** — 1–20 people, target count re-rolls every ~10–20 s.
    * **Slow wander + long idle** on the ring (r ≥ 2 m).
    * **Ring groups (2–5)** — cluster on the ring, linger with subtle shuffle.
    * **Center chill (2–5)** — periodically a small group walks into the 2 m
      center disk (installation chill zone), stands/micro-shuffles, then returns
      to the ring.
    * **Approach spawns** — all new arrivals start at 20 m and walk in.

  `movement` scales all speeds (0.0 = frozen).
  """

  @ring_inner 2.0
  @center_radius 2.0
  # Panel ring radius = aframe panelDiameter / 2 (18 m diameter → 9 m radius).
  @outer_radius 9.0
  @spawn_radius 20.0

  @speed_min 0.25
  @speed_max 0.55

  # Approachers walk briskly from the 20 m spawn to the ring (else it takes ~30 s).
  @approach_speed_min 1.6
  @approach_speed_max 2.6

  @linger_speed 0.08
  @linger_radius 0.45

  @center_linger_speed 0.06

  @waypoint_reached 0.3

  @idle_min_ms 4_000
  @idle_max_ms 10_000

  @count_min 1
  @count_max 20
  @retarget_min_ms 10_000
  @retarget_max_ms 20_000

  @gather_radius 1.0
  @gather_dur_min_ms 12_000
  @gather_dur_max_ms 28_000
  @gather_cooldown_min_ms 2_000
  @gather_cooldown_max_ms 7_000
  @group_size_min 2
  @group_size_max 5

  @center_dur_min_ms 15_000
  @center_dur_max_ms 35_000
  @center_cooldown_min_ms 3_000
  @center_cooldown_max_ms 10_000

  @linger_repick_min_ms 3_000
  @linger_repick_max_ms 7_000
  @center_linger_repick_min_ms 4_000
  @center_linger_repick_max_ms 9_000

  defstruct people: [],
            next_id: 1,
            time_ms: 0.0,
            target_count: 1,
            retarget_at: 0.0,
            gathering: nil,
            gather_next_at: 0.0,
            center_session: nil,
            center_next_at: 0.0

  @type person :: %{id: pos_integer(), x: float(), y: float(), vx: float(), vy: float()}
  @type t :: %__MODULE__{}

  @spec new() :: t()
  def new do
    target = rand_int(5, 12)

    crowd = %__MODULE__{
      target_count: target,
      retarget_at: rand_uniform(@retarget_min_ms, @retarget_max_ms),
      gather_next_at: rand_uniform(@gather_cooldown_min_ms, @gather_cooldown_max_ms),
      center_next_at: rand_uniform(@center_cooldown_min_ms, @center_cooldown_max_ms)
    }

    Enum.reduce(1..target, crowd, fn _, c -> spawn_one(c) end)
  end

  @spec update(t(), float(), float()) :: t()
  def update(crowd, dt, _movement) when dt <= 0, do: crowd

  def update(%__MODULE__{} = crowd, dt, movement) do
    time = crowd.time_ms + dt * 1000.0
    crowd = %{crowd | time_ms: time}

    crowd
    |> maybe_retarget(time)
    |> maintain_population()
    |> manage_center_session(time)
    |> manage_gathering(time)
    |> move_people(dt, movement, time)
  end

  @spec people(t()) :: [person()]
  def people(%__MODULE__{people: people}) do
    Enum.map(people, fn p -> %{id: p.id, x: p.x, y: p.y, vx: p.vx, vy: p.vy} end)
  end

  defp maybe_retarget(%__MODULE__{retarget_at: at} = crowd, time) when time < at, do: crowd

  defp maybe_retarget(crowd, time) do
    target = (crowd.target_count + rand_int(-4, 4)) |> clamp_int(@count_min, @count_max)

    %{
      crowd
      | target_count: target,
        retarget_at: time + rand_uniform(@retarget_min_ms, @retarget_max_ms)
    }
  end

  defp maintain_population(crowd) do
    count = length(crowd.people)

    cond do
      count < crowd.target_count -> spawn_one(crowd)
      count > crowd.target_count -> remove_one(crowd)
      true -> crowd
    end
  end

  @doc """
  Spawns one person at #{@spawn_radius} m walking toward the ring. Additive:
  bumps the target count so maintain_population won't immediately cull it.
  """
  @spec spawn_person(t()) :: t()
  def spawn_person(crowd) do
    target = clamp_int(crowd.target_count + 1, @count_min, @count_max)
    spawn_approaching(%{crowd | target_count: target})
  end

  # Autonomous population spawns on the ring (no boundary crossing). Only the
  # explicit Spawn button creates 20 m approachers, so debug meteors are on demand.
  defp spawn_one(crowd) do
    {x, y} = random_point_in_ring()
    person = new_person(crowd, x, y) |> pick_wander_waypoint()
    %{crowd | people: [person | crowd.people], next_id: crowd.next_id + 1}
  end

  defp spawn_approaching(crowd) do
    {x, y} = random_point_at_spawn_radius()
    {wx, wy} = random_point_in_ring()

    person =
      new_person(crowd, x, y)
      |> Map.merge(%{
        approaching: true,
        wx: wx,
        wy: wy,
        idle_until: 0.0,
        base_speed: rand_uniform(@approach_speed_min, @approach_speed_max)
      })

    %{crowd | people: [person | crowd.people], next_id: crowd.next_id + 1}
  end

  defp new_person(crowd, x, y) do
    %{
      id: crowd.next_id,
      x: x,
      y: y,
      vx: 0.0,
      vy: 0.0,
      base_speed: rand_uniform(@speed_min, @speed_max),
      wx: 0.0,
      wy: 0.0,
      idle_until: rand_uniform(0.0, 3000.0),
      gather: false,
      center: false,
      approaching: false,
      linger_at: 0.0
    }
  end

  defp remove_one(crowd) do
    victim =
      Enum.find(crowd.people, fn p ->
        not p.gather and not Map.get(p, :center, false) and not Map.get(p, :approaching, false)
      end) || List.first(crowd.people)

    %{crowd | people: List.delete(crowd.people, victim)}
  end

  # --- center chill (2 m disk) ---------------------------------------------

  defp manage_center_session(%__MODULE__{center_session: nil} = crowd, time) do
    if time >= crowd.center_next_at and crowd.gathering == nil and
         length(crowd.people) >= @group_size_min do
      start_center_session(crowd, time)
    else
      crowd
    end
  end

  defp manage_center_session(%__MODULE__{center_session: %{until: until}} = crowd, time)
       when time < until,
       do: crowd

  defp manage_center_session(crowd, time) do
    people = Enum.map(crowd.people, fn p -> if Map.get(p, :center, false), do: release_center(p), else: p end)

    %{
      crowd
      | people: people,
        center_session: nil,
        center_next_at: time + rand_uniform(@center_cooldown_min_ms, @center_cooldown_max_ms)
    }
  end

  defp start_center_session(crowd, time) do
    until = time + rand_uniform(@center_dur_min_ms, @center_dur_max_ms)

    group_size =
      crowd.people
      |> length()
      |> min(@group_size_max)
      |> max(@group_size_min)
      |> then(fn max_size -> rand_int(@group_size_min, max_size) end)

    member_ids =
      crowd.people
      |> Enum.reject(fn p -> p.gather end)
      |> Enum.map(& &1.id)
      |> Enum.shuffle()
      |> Enum.take(group_size)
      |> MapSet.new()

    people =
      Enum.map(crowd.people, fn p ->
        if MapSet.member?(member_ids, p.id) do
          {cx, cy} = random_point_in_center()

          %{
            p
            | center: true,
              gather: false,
              idle_until: 0.0,
              linger_at: 0.0,
              base_speed: rand_uniform(@speed_min, @speed_max),
              wx: cx,
              wy: cy
          }
        else
          p
        end
      end)

    %{crowd | people: people, center_session: %{until: until}}
  end

  defp release_center(person) do
    %{person | center: false, idle_until: 0.0, linger_at: 0.0, base_speed: rand_uniform(@speed_min, @speed_max)}
    |> pick_wander_waypoint()
  end

  # --- ring gatherings -----------------------------------------------------

  defp manage_gathering(%__MODULE__{gathering: nil} = crowd, time) do
    if time >= crowd.gather_next_at and crowd.center_session == nil and
         length(crowd.people) >= @group_size_min do
      start_gathering(crowd, time)
    else
      crowd
    end
  end

  defp manage_gathering(%__MODULE__{gathering: %{until: until}} = crowd, time) when time < until,
    do: crowd

  defp manage_gathering(crowd, time) do
    people = Enum.map(crowd.people, fn p -> if p.gather, do: release_member(p), else: p end)

    %{
      crowd
      | people: people,
        gathering: nil,
        gather_next_at: time + rand_uniform(@gather_cooldown_min_ms, @gather_cooldown_max_ms)
    }
  end

  defp start_gathering(crowd, time) do
    {cx, cy} = random_point_in_ring()
    until = time + rand_uniform(@gather_dur_min_ms, @gather_dur_max_ms)

    group_size =
      crowd.people
      |> length()
      |> min(@group_size_max)
      |> max(@group_size_min)
      |> then(fn max_size -> rand_int(@group_size_min, max_size) end)

    member_ids =
      crowd.people
      |> Enum.reject(fn p -> Map.get(p, :center, false) end)
      |> Enum.map(& &1.id)
      |> Enum.shuffle()
      |> Enum.take(group_size)
      |> MapSet.new()

    people =
      Enum.map(crowd.people, fn p ->
        if MapSet.member?(member_ids, p.id) do
          {ox, oy} = random_offset(@gather_radius)

          %{
            p
            | gather: true,
              center: false,
              idle_until: 0.0,
              linger_at: 0.0,
              base_speed: rand_uniform(@speed_min, @speed_max),
              wx: cx + ox,
              wy: cy + oy
          }
        else
          p
        end
      end)

    %{crowd | people: people, gathering: %{x: cx, y: cy, until: until}}
  end

  defp release_member(person) do
    %{person | gather: false, idle_until: 0.0, linger_at: 0.0, base_speed: rand_uniform(@speed_min, @speed_max)}
    |> pick_wander_waypoint()
  end

  # --- movement ------------------------------------------------------------

  defp move_people(crowd, dt, movement, time) do
    %{crowd | people: Enum.map(crowd.people, &move_person(&1, crowd, dt, movement, time))}
  end

  defp move_person(%{approaching: true} = person, _crowd, dt, movement, _time) do
    person
    |> walk_toward(dt, movement)
    |> maybe_release_approaching()
  end

  defp move_person(%{idle_until: until} = person, _crowd, _dt, _movement, time) when until > time do
    %{person | vx: 0.0, vy: 0.0}
  end

  defp move_person(%{center: true} = person, _crowd, dt, movement, time) do
    person = maybe_linger_center_waypoint(person, time)
    walk_toward(person, dt, movement)
  end

  defp move_person(%{gather: true} = person, crowd, dt, movement, time) do
    person = maybe_linger_waypoint(person, crowd, time)
    walk_toward(person, dt, movement)
  end

  defp move_person(person, _crowd, dt, movement, time) do
    walk_toward(person, dt, movement)
    |> then(fn p -> if at_waypoint?(p), do: reached(p, time), else: p end)
  end

  defp walk_toward(person, dt, movement) do
    dx = person.wx - person.x
    dy = person.wy - person.y
    dist = :math.sqrt(dx * dx + dy * dy)

    if dist <= @waypoint_reached do
      %{person | x: person.wx, y: person.wy, vx: 0.0, vy: 0.0}
    else
      speed = person.base_speed * movement
      step = min(speed * dt, dist)
      nx = person.x + dx / dist * step
      ny = person.y + dy / dist * step
      %{person | x: nx, y: ny, vx: (nx - person.x) / max(dt, 0.001), vy: (ny - person.y) / max(dt, 0.001)}
    end
  end

  defp maybe_release_approaching(%{approaching: true} = person) do
    r = :math.sqrt(person.x * person.x + person.y * person.y)

    if at_waypoint?(person) or r <= @outer_radius do
      %{person | approaching: false} |> pick_wander_waypoint()
    else
      person
    end
  end

  defp maybe_release_approaching(person), do: person

  defp at_waypoint?(person) do
    dx = person.wx - person.x
    dy = person.wy - person.y
    :math.sqrt(dx * dx + dy * dy) <= @waypoint_reached
  end

  defp maybe_linger_center_waypoint(%{center: true} = person, time) do
    linger_at = Map.get(person, :linger_at, 0.0)

    if at_waypoint?(person) and time >= linger_at do
      {cx, cy} = random_point_in_center()

      %{
        person
        | wx: cx,
          wy: cy,
          base_speed: @center_linger_speed,
          linger_at: time + rand_uniform(@center_linger_repick_min_ms, @center_linger_repick_max_ms)
      }
    else
      person
    end
  end

  defp maybe_linger_waypoint(%{gather: true} = person, %{gathering: %{x: cx, y: cy}}, time) do
    linger_at = Map.get(person, :linger_at, 0.0)

    if at_waypoint?(person) and time >= linger_at do
      {ox, oy} = random_offset(@linger_radius)

      %{
        person
        | wx: cx + ox,
          wy: cy + oy,
          base_speed: @linger_speed,
          linger_at: time + rand_uniform(@linger_repick_min_ms, @linger_repick_max_ms)
      }
    else
      person
    end
  end

  defp maybe_linger_waypoint(person, _crowd, _time), do: person

  defp reached(person, time) do
    %{person | idle_until: time + rand_uniform(@idle_min_ms, @idle_max_ms)}
    |> pick_wander_waypoint()
  end

  # --- geometry helpers ----------------------------------------------------

  defp pick_wander_waypoint(person) do
    {wx, wy} = near_point({person.x, person.y})
    %{person | wx: wx, wy: wy}
  end

  defp near_point(from) do
    Enum.find_value(1..8, fn _ ->
      candidate = random_point_in_ring()
      d = dist2(candidate, from)
      if d >= 1.0 and d <= 4.5, do: candidate
    end) || random_point_in_ring()
  end

  defp random_point_in_ring do
    r = :math.sqrt(rand_uniform(@ring_inner * @ring_inner, @outer_radius * @outer_radius))
    a = :rand.uniform() * 2.0 * :math.pi()
    {:math.cos(a) * r, :math.sin(a) * r}
  end

  defp random_point_at_spawn_radius do
    a = :rand.uniform() * 2.0 * :math.pi()
    {:math.cos(a) * @spawn_radius, :math.sin(a) * @spawn_radius}
  end

  # Uniform disk inside the 2 m center chill zone (keep a small margin from origin).
  defp random_point_in_center do
    r = :math.sqrt(rand_uniform(0.35 * 0.35, @center_radius * @center_radius))
    a = :rand.uniform() * 2.0 * :math.pi()
    {:math.cos(a) * r, :math.sin(a) * r}
  end

  defp random_offset(radius) do
    r = :math.sqrt(rand_uniform(0.0, radius * radius))
    a = :rand.uniform() * 2.0 * :math.pi()
    {:math.cos(a) * r, :math.sin(a) * r}
  end

  defp dist2({ax, ay}, {bx, by}) do
    dx = ax - bx
    dy = ay - by
    :math.sqrt(dx * dx + dy * dy)
  end

  defp rand_uniform(lo, hi), do: lo + :rand.uniform() * (hi - lo)

  defp rand_int(lo, hi), do: lo + :rand.uniform(hi - lo + 1) - 1

  defp clamp_int(value, lo, hi), do: value |> max(lo) |> min(hi)
end
