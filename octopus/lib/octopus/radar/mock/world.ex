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
    * `:lounging` — sits on the central platform near a group anchor for a long
      time at near-zero speed and a lowered (sitting) height
    * `:circling` — strolls a loop just outside the platform edge

  Which behavior is picked depends on whether the person is currently on the
  central platform (the "chill zone", radius `platform_radius_m`): on it people
  mostly lounge in small groups, off it they mostly wander.

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
  # modulated at runtime by the activity "entropy" (see `pick_behavior/2`).
  @slow_speed {0.2, 0.5}
  @fast_speed {0.8, 1.4}
  @stand_ms {2_000, 6_000}
  @wander_ms {2_000, 5_000}
  @z_range {1.6, 1.85}

  # Per-tick spawn/despawn probabilities (10 Hz tick → these are per 100 ms).
  @spawn_prob 0.05
  @despawn_prob 0.01

  # --- Central platform ("chill zone") --------------------------------------
  # The central platform is a disk of radius `platform_radius_m` (read live from
  # `Octopus.Params.Sim3d`). People on it mostly sit (lounge) in small groups
  # for long periods, sit lower (smaller z), or stroll/circle around it; outside
  # they wander as before. A small center keepout keeps people off the mast /
  # lean post in the middle.
  @default_platform_radius_m 2.5
  @center_keepout_m 0.5

  # Lounging = sitting on the platform: a long dwell at near-zero speed, reached
  # by a slow stroll, with a lowered (sitting) height.
  @lounge_ms {15_000, 60_000}
  @stroll_speed {0.2, 0.4}
  @sit_z {0.7, 1.1}

  # Circling = strolling a loop just outside the platform edge.
  @circle_ms {4_000, 9_000}
  @circle_speed {0.3, 0.8}

  # Social cluster points on the platform. People gravitate toward an anchor and
  # sit within `@anchor_jitter_m` of it; an anchor holds at most `@group_cap`
  # loungers (counted within `@group_radius_m`) so groups stay small.
  @anchor_count 3
  @group_cap 4
  @anchor_jitter_m 0.5
  @group_radius_m 1.0

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

  @doc "Current population cap (`1..Octopus.Radar.max_people_limit/0`)."
  @spec max_people() :: pos_integer()
  def max_people, do: GenServer.call(__MODULE__, :max_people)

  @doc "Set the population cap (clamped to `1..Octopus.Radar.max_people_limit/0`)."
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
    platform_radius_m = clamp_platform(configured_platform_radius_m(), radius_m)

    # Track the Sim3D platform radius so the chill zone matches the 3D view.
    Phoenix.PubSub.subscribe(Octopus.PubSub, Octopus.Params.Sim3d.topic())

    state = %{
      radius_m: radius_m,
      platform_radius_m: platform_radius_m,
      group_anchors: gen_anchors(platform_radius_m, @anchor_count),
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

  # The Sim3D platform radius drives the chill zone. Re-derive the anchors on
  # change so groups stay on the (possibly resized) platform.
  def handle_info({:platform_radius_m, value}, state) do
    platform_radius_m = clamp_platform(value, state.radius_m)

    {:noreply,
     %{
       state
       | platform_radius_m: platform_radius_m,
         group_anchors: gen_anchors(platform_radius_m, @anchor_count)
     }}
  end

  # Ignore the other Sim3D parameter broadcasts on the shared topic.
  def handle_info(_msg, state), do: {:noreply, state}

  ## Simulation

  defp step(%{mode: :off} = state), do: state
  defp step(%{frozen: true} = state), do: state

  defp step(state) do
    now = System.monotonic_time(:millisecond)
    dt = @tick_ms / 1000.0
    factor = state.entropy / 100.0
    anchors = state.group_anchors
    platform_r = state.platform_radius_m
    occ = anchor_occupancy(state.people, anchors)

    people =
      state.people
      |> Enum.map(&update_person(&1, now, dt, state.radius_m, platform_r, factor, anchors, occ))

    {people, next_id} =
      manage_population(
        people,
        state.max_people,
        state.radius_m,
        now,
        state.next_id,
        factor,
        anchors
      )

    %{state | people: people, next_id: next_id}
  end

  defp update_person(person, now, dt, radius, platform_r, factor, anchors, occ) do
    person =
      if now >= person.until_ms,
        do: retarget(person, now, radius, platform_r, factor, anchors, occ),
        else: person

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

  # Pick the next behavior. Whether the person is currently on the central
  # platform biases the choice heavily: on the platform they mostly lounge in
  # small groups (and sometimes circle or leave); off it they sometimes head in
  # to chill or circle, otherwise they wander as before. `factor` (entropy/100)
  # shifts the balance from chilling toward roaming.
  defp retarget(person, now, radius, platform_r, factor, anchors, occ) do
    on_platform? = :math.sqrt(person.x * person.x + person.y * person.y) <= platform_r
    roll = :rand.uniform()
    p_lounge = clampf(0.75 - 0.4 * factor, 0.2, 0.85)
    p_circle = clampf(0.1 + 0.15 * factor, 0.05, 0.35)
    p_seek = clampf(0.45 - 0.25 * factor, 0.1, 0.5)

    cond do
      on_platform? and roll < p_lounge ->
        lounge(person, now, radius, platform_r, factor, anchors, occ)

      on_platform? and roll < p_lounge + p_circle ->
        circle(person, now, platform_r, factor)

      not on_platform? and roll < p_seek ->
        lounge(person, now, radius, platform_r, factor, anchors, occ)

      not on_platform? and roll < p_seek + p_circle ->
        circle(person, now, platform_r, factor)

      true ->
        wander_or_stand(person, now, radius, factor)
    end
  end

  # The original off-platform behavior: mostly stand, otherwise stroll/walk to a
  # random point. Resets the height to standing in case the person was sitting.
  defp wander_or_stand(person, now, radius, factor) do
    person = %{person | z: rand_in(@z_range)}

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

  # Sit on the platform near a group anchor: a slow stroll to a spot, then a
  # long dwell at a lowered (sitting) height. If every anchor is full the person
  # gives up on chilling and roams instead.
  defp lounge(person, now, radius, platform_r, factor, anchors, occ) do
    case choose_anchor(anchors, occ) do
      nil ->
        wander_or_stand(person, now, radius, factor)

      anchor ->
        {tx, ty} =
          anchor
          |> jitter_around(@anchor_jitter_m)
          |> keep_out_center()
          |> clamp_point(platform_r)

        dwell = round(rand_in(@lounge_ms) * (1.0 - 0.5 * factor))

        %{
          person
          | behavior: :lounging,
            speed: rand_in(@stroll_speed),
            target_x: tx,
            target_y: ty,
            z: rand_in(@sit_z),
            until_ms: now + max(dwell, 2_000)
        }
    end
  end

  # Stroll a loop just outside the platform edge: advance the current bearing by
  # a step in a random direction and aim there at standing height.
  defp circle(person, now, platform_r, factor) do
    orbit_r = platform_r + rand_in({0.3, 1.0})
    theta = :math.atan2(person.y, person.x)
    dir = if :rand.uniform() < 0.5, do: 1.0, else: -1.0
    next = theta + dir * rand_in({0.4, 1.0})

    %{
      person
      | behavior: :circling,
        speed: rand_in(@circle_speed) * (0.6 + 0.4 * factor),
        target_x: orbit_r * :math.cos(next),
        target_y: orbit_r * :math.sin(next),
        z: rand_in(@z_range),
        until_ms: now + rand_in(@circle_ms)
    }
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

  defp manage_population(people, max_people, radius, now, next_id, factor, anchors) do
    count = length(people)

    cond do
      count > max_people ->
        {Enum.take_random(people, max_people), next_id}

      count == 0 ->
        {[spawn_person(radius, now, next_id, factor, anchors)], next_id + 1}

      count < max_people and :rand.uniform() < @spawn_prob ->
        {[spawn_person(radius, now, next_id, factor, anchors) | people], next_id + 1}

      count > 1 and :rand.uniform() < @despawn_prob ->
        {Enum.drop(Enum.shuffle(people), 1), next_id}

      true ->
        {people, next_id}
    end
  end

  # People enter from the world border and then head inward, rather than
  # popping into existence in the middle of the scene. About half head straight
  # for a platform anchor so the chill zone fills up realistically; the rest
  # roam toward a random point.
  defp spawn_person(radius, now, id, factor, anchors) do
    usable = radius - @edge_margin_m
    theta = 2.0 * :math.pi() * :rand.uniform()
    x = usable * :math.cos(theta)
    y = usable * :math.sin(theta)

    {tx, ty} =
      if anchors != [] and :rand.uniform() < 0.5 do
        anchors |> Enum.random() |> jitter_around(@anchor_jitter_m) |> keep_out_center()
      else
        random_point_in_disk(usable * 0.7)
      end

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

  ## Platform / group helpers

  # Social cluster points on the platform ring, between the center keepout and
  # just inside the platform edge.
  defp gen_anchors(platform_r, n) do
    inner = @center_keepout_m + 0.2
    outer = max(platform_r - 0.3, inner + 0.1)

    for _ <- 1..n do
      theta = 2.0 * :math.pi() * :rand.uniform()
      r = inner + :rand.uniform() * (outer - inner)
      %{x: r * :math.cos(theta), y: r * :math.sin(theta)}
    end
  end

  # Count of lounging people within `@group_radius_m` of each anchor, as a list
  # aligned with the anchor list by index.
  defp anchor_occupancy(people, anchors) do
    loungers = Enum.filter(people, &(&1.behavior == :lounging))

    Enum.map(anchors, fn a ->
      Enum.count(loungers, fn p -> :math.sqrt(sq(p.x - a.x) + sq(p.y - a.y)) <= @group_radius_m end)
    end)
  end

  # Pick an anchor to sit at: prefer joining an anchor that already has a small
  # group (so clusters form), otherwise take a free one. Anchors at the group
  # cap are skipped; if all are full, return nil (caller roams instead).
  defp choose_anchor([], _occ), do: nil

  defp choose_anchor(anchors, occ) do
    indexed = Enum.with_index(anchors)
    joinable = Enum.filter(indexed, fn {_a, i} -> c = Enum.at(occ, i); c > 0 and c < @group_cap end)
    empty = Enum.filter(indexed, fn {_a, i} -> Enum.at(occ, i) == 0 end)

    cond do
      joinable != [] and :rand.uniform() < 0.7 -> joinable |> Enum.random() |> elem(0)
      joinable ++ empty != [] -> (joinable ++ empty) |> Enum.random() |> elem(0)
      true -> nil
    end
  end

  defp jitter_around(%{x: x, y: y}, max_offset) do
    {dx, dy} = random_point_in_disk(max_offset)
    {x + dx, y + dy}
  end

  # Push a point radially out to the center keepout so nobody sits on the mast /
  # lean post in the very middle of the platform.
  defp keep_out_center({x, y}) do
    dist = :math.sqrt(x * x + y * y)

    if dist > 0.0 and dist < @center_keepout_m do
      scale = @center_keepout_m / dist
      {x * scale, y * scale}
    else
      {x, y}
    end
  end

  # Clamp a point to the platform disk (used for lounge targets).
  defp clamp_point({x, y}, radius) do
    dist = :math.sqrt(x * x + y * y)

    if dist > radius and dist > 0.0 do
      scale = radius / dist
      {x * scale, y * scale}
    else
      {x, y}
    end
  end

  defp sq(v), do: v * v

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

  # The cap scales with the number of configured sensors (each real sensor can
  # track up to ~10 people); see `Octopus.Radar.max_people_limit/0`.
  defp clamp_max_people(n), do: n |> max(1) |> min(Radar.max_people_limit())

  defp clamp_entropy(n), do: n |> max(0) |> min(100)

  defp clampf(v, lo, hi), do: v |> max(lo) |> min(hi)

  defp configured_radius_m do
    Application.get_env(:octopus, Octopus.Radar, [])
    |> Keyword.get(:mock, [])
    |> Keyword.get(:radius_m, @default_radius_m)
  end

  defp configured_platform_radius_m do
    Octopus.Params.Sim3d.platform_radius_m()
  rescue
    _ -> @default_platform_radius_m
  end

  # Keep the platform strictly inside the world disk, and never degenerate.
  defp clamp_platform(value, radius) when is_number(value) do
    value |> max(0.1) |> min(radius - @edge_margin_m)
  end

  defp clamp_platform(_value, radius), do: clamp_platform(@default_platform_radius_m, radius)
end
