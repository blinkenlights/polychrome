defmodule Octopus.Apps.Collective.MockCrowd do
  @moduledoc """
  Self-contained mock of people walking around the installation ring.

  Each person mirrors the fields of `Octopus.Radar.Track` (`x`, `y`, `vx`, `vy`
  in meters / m/s, origin at the ring center) so that swapping this mock for the
  real radar feed (`Octopus.Radar.subscribe/0`) — or Tim's mock server — is a pure
  source replacement; consumers see the same person maps either way.

  Behaviour, ported in spirit from the browser-side `humanWorld.ts`:

    * **Dynamic population** — the crowd size drifts on its own between 1 and 20.
      People spawn at the ring and despawn over time; the target count re-rolls
      every several seconds.
    * **Wander + idle** — people walk to a waypoint, pause briefly, pick a new one.
    * **Groups** — every so often a cluster forms: a subset gathers at a common
      point and stands still together for a while, then disperses.

  `movement` (passed to `update/3`) is a global speed multiplier (0.0 = frozen).
  An internal millisecond clock (`time_ms`) advances with `dt`, so all timing is
  deterministic and independent of wall-clock.
  """

  # Ring geometry in meters (people wander in this band around the center).
  @inner_radius 2.0
  @outer_radius 9.0

  # Base walking speed range in m/s (before the movement multiplier).
  @speed_min 0.7
  @speed_max 1.3

  @waypoint_reached 0.35

  # Idle pause (ms) after reaching a wander waypoint.
  @idle_min_ms 800
  @idle_max_ms 4000

  # Population bounds and how often the target count re-rolls.
  @count_min 1
  @count_max 20
  @retarget_min_ms 7_000
  @retarget_max_ms 16_000

  # Group gatherings.
  @gather_radius 1.3
  @gather_dur_min_ms 5_000
  @gather_dur_max_ms 12_000
  @gather_cooldown_min_ms 4_000
  @gather_cooldown_max_ms 11_000
  @gather_member_fraction 0.6

  defstruct people: [],
            next_id: 1,
            time_ms: 0.0,
            target_count: 1,
            retarget_at: 0.0,
            gathering: nil,
            gather_next_at: 0.0

  @type person :: %{id: pos_integer(), x: float(), y: float(), vx: float(), vy: float()}
  @type t :: %__MODULE__{}

  @doc "Creates a crowd with a random initial population and autonomous behaviour."
  @spec new() :: t()
  def new do
    target = rand_int(5, 15)

    crowd = %__MODULE__{
      target_count: target,
      retarget_at: rand_uniform(@retarget_min_ms, @retarget_max_ms),
      gather_next_at: rand_uniform(@gather_cooldown_min_ms, @gather_cooldown_max_ms)
    }

    Enum.reduce(1..target, crowd, fn _, c -> spawn_person(c) end)
  end

  @doc """
  Advances the crowd by `dt` seconds. `movement` (>= 0.0) scales walking speed;
  at 0.0 everyone is frozen in place.
  """
  @spec update(t(), float(), float()) :: t()
  def update(crowd, dt, _movement) when dt <= 0, do: crowd

  def update(%__MODULE__{} = crowd, dt, movement) do
    time = crowd.time_ms + dt * 1000.0
    crowd = %{crowd | time_ms: time}

    crowd
    |> maybe_retarget(time)
    |> maintain_population()
    |> manage_gathering(time)
    |> move_people(dt, movement, time)
  end

  @doc "Returns the radar-track-shaped person maps for consumers."
  @spec people(t()) :: [person()]
  def people(%__MODULE__{people: people}) do
    Enum.map(people, fn p -> %{id: p.id, x: p.x, y: p.y, vx: p.vx, vy: p.vy} end)
  end

  # --- population ----------------------------------------------------------

  defp maybe_retarget(%__MODULE__{retarget_at: at} = crowd, time) when time < at, do: crowd

  defp maybe_retarget(crowd, time) do
    target = (crowd.target_count + rand_int(-6, 6)) |> clamp_int(@count_min, @count_max)
    %{crowd | target_count: target, retarget_at: time + rand_uniform(@retarget_min_ms, @retarget_max_ms)}
  end

  # Adjust by at most one person per tick for gradual entrances/exits.
  defp maintain_population(crowd) do
    count = length(crowd.people)

    cond do
      count < crowd.target_count -> spawn_person(crowd)
      count > crowd.target_count -> remove_one(crowd)
      true -> crowd
    end
  end

  defp spawn_person(crowd) do
    {x, y} = random_point_in_ring()

    person =
      %{
        id: crowd.next_id,
        x: x,
        y: y,
        vx: 0.0,
        vy: 0.0,
        base_speed: rand_uniform(@speed_min, @speed_max),
        wx: 0.0,
        wy: 0.0,
        idle_until: 0.0,
        gather: false
      }
      |> pick_wander_waypoint()

    %{crowd | people: [person | crowd.people], next_id: crowd.next_id + 1}
  end

  # Prefer removing someone who isn't part of a standing group.
  defp remove_one(crowd) do
    victim = Enum.find(crowd.people, &(not &1.gather)) || List.first(crowd.people)
    %{crowd | people: List.delete(crowd.people, victim)}
  end

  # --- gatherings ----------------------------------------------------------

  defp manage_gathering(%__MODULE__{gathering: nil} = crowd, time) do
    if time >= crowd.gather_next_at and length(crowd.people) >= 2 do
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

    people =
      Enum.map(crowd.people, fn p ->
        if not p.gather and :rand.uniform() < @gather_member_fraction do
          {ox, oy} = random_offset(@gather_radius)
          %{p | gather: true, idle_until: 0.0, wx: cx + ox, wy: cy + oy}
        else
          p
        end
      end)

    %{crowd | people: people, gathering: %{x: cx, y: cy, until: until}}
  end

  defp release_member(person) do
    %{person | gather: false, idle_until: 0.0} |> pick_wander_waypoint()
  end

  # --- movement ------------------------------------------------------------

  defp move_people(crowd, dt, movement, time) do
    %{crowd | people: Enum.map(crowd.people, &move_person(&1, crowd, dt, movement, time))}
  end

  defp move_person(%{idle_until: until} = person, _crowd, _dt, _movement, time) when until > time do
    %{person | vx: 0.0, vy: 0.0}
  end

  defp move_person(person, crowd, dt, movement, time) do
    dx = person.wx - person.x
    dy = person.wy - person.y
    dist = :math.sqrt(dx * dx + dy * dy)

    if dist <= @waypoint_reached do
      reached(%{person | x: person.wx, y: person.wy, vx: 0.0, vy: 0.0}, crowd, time)
    else
      speed = person.base_speed * movement
      step = min(speed * dt, dist)
      nx = person.x + dx / dist * step
      ny = person.y + dy / dist * step
      %{person | x: nx, y: ny, vx: (nx - person.x) / dt, vy: (ny - person.y) / dt}
    end
  end

  # Group members stand until the gathering ends; wanderers pause then move on.
  defp reached(%{gather: true} = person, %{gathering: %{until: until}}, _time) do
    %{person | idle_until: until}
  end

  defp reached(person, _crowd, time) do
    %{person | idle_until: time + rand_uniform(@idle_min_ms, @idle_max_ms)}
    |> pick_wander_waypoint()
  end

  # --- geometry helpers ----------------------------------------------------

  defp pick_wander_waypoint(person) do
    {wx, wy} = far_point({person.x, person.y})
    %{person | wx: wx, wy: wy}
  end

  # A ring point at least 2 m from `from` (up to 8 tries), to avoid tiny hops.
  defp far_point(from) do
    Enum.find_value(1..8, fn _ ->
      candidate = random_point_in_ring()
      if dist2(candidate, from) >= 2.0, do: candidate
    end) || random_point_in_ring()
  end

  defp random_point_in_ring do
    r = :math.sqrt(rand_uniform(@inner_radius * @inner_radius, @outer_radius * @outer_radius))
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

  # --- numeric helpers -----------------------------------------------------

  defp rand_uniform(lo, hi), do: lo + :rand.uniform() * (hi - lo)

  defp rand_int(lo, hi), do: lo + :rand.uniform(hi - lo + 1) - 1

  defp clamp_int(value, lo, hi), do: value |> max(lo) |> min(hi)
end
