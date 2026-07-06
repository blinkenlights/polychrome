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
    * `:grouping` — stands in a small group (2-6) around a fixed off-platform
      gathering spot, only shuffling slightly in place

  Which behavior is picked depends on whether the person is currently on the
  central platform (the "chill zone", radius `platform_radius_m`): on it people
  mostly lounge in small groups, off it a large share stand in small groups and
  the rest wander.

  The live population is kept within `1..max_people`; people appear and
  disappear over time. `max_people` is operator-adjustable at runtime.

  ## Ground-truth feed

  On every tick the current snapshot is broadcast as `{:mock_world, objects}`
  on `"#{Octopus.Radar.topic()}:world"` so the UI can draw true positions.
  """

  use GenServer

  alias Octopus.Radar

  @tick_ms 100
  @default_radius_m 9.0
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

  # Population dynamics (10 Hz tick). When below the cap we let up to
  # `@spawn_burst` people enter per tick so raising the "max people" slider fills
  # in promptly (a steady stream walking in from the edge); above the cap we let
  # up to `@despawn_burst` leave per tick (outermost first) so lowering it drains
  # gradually instead of popping people out. `@despawn_prob` is the ambient
  # per-tick chance of one person leaving once the cap is reached, to keep the
  # crowd lightly breathing.
  @spawn_burst 3
  @despawn_burst 3
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
  @lounge_ms {10_000, 40_000}
  @stroll_speed {0.2, 0.4}
  @sit_z {0.7, 1.1}

  # Circling = strolling a loop just outside the platform edge.
  @circle_ms {4_000, 9_000}
  @circle_speed {0.3, 0.8}

  # Social cluster points on the platform. People gravitate toward an anchor and
  # sit within `@anchor_jitter_m` of it; an anchor holds at most `@group_cap`
  # loungers (counted within `@group_radius_m`) so groups stay small.
  @anchor_count 2
  @group_cap 3
  @anchor_jitter_m 0.5
  @group_radius_m 1.0

  # --- World-wide standing groups -------------------------------------------
  # Off the platform, a portion of people gather in small standing clusters
  # around fixed "gathering" spots and only shuffle slightly in place, instead
  # of wandering across the disk. Group size 2-6 emerges from the join-bias in
  # `choose_anchor/3` plus the `@group_max` per-anchor cap.
  @gather_anchor_count 6
  @group_max 6
  # Spread when first joining a group vs. the small in-place shuffle afterwards.
  @group_join_jitter_m 0.8
  @group_shuffle_m 0.5
  # Standing time in the group, and the gap between tiny in-place shuffles.
  @group_dwell_ms {6_000, 20_000}
  @group_shuffle_ms {2_000, 6_000}
  # Keepout pushing grouping people just outside the platform edge.
  @platform_margin_m 0.4

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
      gather_anchors: gen_gather_anchors(platform_radius_m, radius_m, @gather_anchor_count),
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
         group_anchors: gen_anchors(platform_radius_m, @anchor_count),
         gather_anchors:
           gen_gather_anchors(platform_radius_m, state.radius_m, @gather_anchor_count)
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

    ctx = %{
      radius: state.radius_m,
      platform_r: state.platform_radius_m,
      factor: state.entropy / 100.0,
      platform_anchors: state.group_anchors,
      platform_occ: occupancy(state.people, state.group_anchors, :lounging),
      gather_anchors: state.gather_anchors,
      gather_occ: occupancy(state.people, state.gather_anchors, :grouping)
    }

    people = Enum.map(state.people, &update_person(&1, now, dt, ctx))

    {people, next_id} = manage_population(people, state.max_people, now, state.next_id, ctx)

    %{state | people: people, next_id: next_id}
  end

  defp update_person(person, now, dt, ctx) do
    person = if now >= person.until_ms, do: retarget(person, now, ctx), else: person

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
      clamp_to_disk(x, y, vx, vy, person.target_x, person.target_y, ctx.radius)

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
  # platform biases the choice heavily.
  defp retarget(person, now, ctx) do
    on_platform? = :math.sqrt(person.x * person.x + person.y * person.y) <= ctx.platform_r
    roll = :rand.uniform()

    if on_platform?,
      do: retarget_on_platform(person, now, ctx, roll),
      else: retarget_off_platform(person, now, ctx, roll)
  end

  # On the platform people mostly lounge in small groups, sometimes circle, and
  # rarely get up and wander off.
  defp retarget_on_platform(person, now, ctx, roll) do
    factor = ctx.factor
    # Loungers commit less and drift off the platform more often (keeps the
    # chill-zone population small); minimal edge-circling.
    p_lounge = clampf(0.45 - 0.30 * factor, 0.12, 0.55)
    p_circle = clampf(0.05 + 0.08 * factor, 0.02, 0.20)

    cond do
      roll < p_lounge -> lounge(person, now, ctx)
      roll < p_lounge + p_circle -> circle(person, now, ctx)
      true -> wander_or_stand(person, now, ctx)
    end
  end

  # Off the platform a large share head onto the platform to chill, stand in a
  # small group, or circle the edge; only the remainder wanders. `factor`
  # (entropy/100) shifts the balance from chilling/standing toward roaming.
  defp retarget_off_platform(person, now, ctx, roll) do
    factor = ctx.factor
    # Very little inflow toward the platform (p_seek) and barely any near-edge
    # circling, so the crowd spreads out into standing groups across the disk
    # (mostly out near the rim) instead of piling up on/around the chill zone.
    p_seek = clampf(0.08 - 0.05 * factor, 0.03, 0.10)
    p_group = clampf(0.55 - 0.15 * factor, 0.30, 0.65)
    p_circle = clampf(0.04 + 0.05 * factor, 0.02, 0.12)

    cond do
      roll < p_seek -> lounge(person, now, ctx)
      roll < p_seek + p_group -> group(person, now, ctx)
      roll < p_seek + p_group + p_circle -> circle(person, now, ctx)
      true -> wander_or_stand(person, now, ctx)
    end
  end

  # The original off-platform behavior: mostly stand, otherwise stroll/walk to a
  # random point. Resets the height to standing in case the person was sitting.
  defp wander_or_stand(person, now, ctx) do
    radius = ctx.radius
    factor = ctx.factor
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
  defp lounge(person, now, ctx) do
    case choose_anchor(ctx.platform_anchors, ctx.platform_occ, @group_cap) do
      nil ->
        wander_or_stand(person, now, ctx)

      anchor ->
        {tx, ty} =
          anchor
          |> jitter_around(@anchor_jitter_m)
          |> keep_out_center()
          |> clamp_point(ctx.platform_r)

        dwell = round(rand_in(@lounge_ms) * (1.0 - 0.5 * ctx.factor))

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
  defp circle(person, now, ctx) do
    orbit_r = ctx.platform_r + rand_in({0.3, 1.0})
    theta = :math.atan2(person.y, person.x)
    dir = if :rand.uniform() < 0.5, do: 1.0, else: -1.0
    next = theta + dir * rand_in({0.4, 1.0})

    %{
      person
      | behavior: :circling,
        speed: rand_in(@circle_speed) * (0.6 + 0.4 * ctx.factor),
        target_x: orbit_r * :math.cos(next),
        target_y: orbit_r * :math.sin(next),
        z: rand_in(@z_range),
        until_ms: now + rand_in(@circle_ms)
    }
  end

  # Stand in a small group around an off-platform gathering spot. If already
  # parked at a nearby anchor, just do a tiny in-place shuffle (groups stay put);
  # otherwise pick an anchor with room and walk over to join. If all anchors are
  # full the person roams instead.
  defp group(person, now, ctx) do
    case nearest_anchor(person, ctx.gather_anchors, @group_radius_m) do
      nil ->
        case choose_anchor(ctx.gather_anchors, ctx.gather_occ, @group_max) do
          nil -> wander_or_stand(person, now, ctx)
          anchor -> walk_to_group(person, anchor, @group_join_jitter_m, @group_dwell_ms, now, ctx)
        end

      anchor ->
        walk_to_group(person, anchor, @group_shuffle_m, @group_shuffle_ms, now, ctx)
    end
  end

  # Aim at a spot near `anchor` at standing height; the move is a slow stroll and
  # the target is kept inside the world disk and just outside the platform, so
  # groups never drift into the chill zone. On arrival `update_person` zeroes the
  # speed, leaving the person standing until the next shuffle.
  defp walk_to_group(person, anchor, jitter, dwell_range, now, ctx) do
    {tx, ty} =
      anchor
      |> jitter_around(jitter)
      |> clamp_point(ctx.radius - @edge_margin_m)
      |> outside_platform(ctx.platform_r)

    %{
      person
      | behavior: :grouping,
        speed: rand_in(@stroll_speed),
        target_x: tx,
        target_y: ty,
        z: rand_in(@z_range),
        until_ms: now + rand_in(dwell_range)
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

  defp manage_population(people, max_people, now, next_id, ctx) do
    count = length(people)

    cond do
      count > max_people ->
        n = min(count - max_people, @despawn_burst)
        {drop_outermost(people, n), next_id}

      count < max_people ->
        n = min(max_people - count, @spawn_burst)
        spawn_many(n, people, now, next_id, ctx)

      count > 1 and :rand.uniform() < @despawn_prob ->
        {Enum.drop(Enum.shuffle(people), 1), next_id}

      true ->
        {people, next_id}
    end
  end

  # Remove the `n` people farthest from the center, so the crowd thins from the
  # edges inward (people leaving the scene) rather than vanishing at random.
  defp drop_outermost(people, n) when n > 0 do
    people
    |> Enum.sort_by(fn p -> -(p.x * p.x + p.y * p.y) end)
    |> Enum.drop(n)
  end

  defp drop_outermost(people, _n), do: people

  defp spawn_many(0, people, _now, next_id, _ctx), do: {people, next_id}

  defp spawn_many(n, people, now, next_id, ctx) when n > 0 do
    spawn_many(
      n - 1,
      [spawn_person(now, next_id, ctx) | people],
      now,
      next_id + 1,
      ctx
    )
  end

  # People enter from the world border and then head inward, rather than
  # popping into existence in the middle of the scene. The target is split so
  # standing groups dominate while the chill zone fills only modestly: ~8% aim
  # for a platform anchor, ~50% for an off-platform gathering spot, the rest
  # roam toward a random point.
  defp spawn_person(now, id, ctx) do
    usable = ctx.radius - @edge_margin_m
    theta = 2.0 * :math.pi() * :rand.uniform()
    x = usable * :math.cos(theta)
    y = usable * :math.sin(theta)
    roll = :rand.uniform()

    {tx, ty} =
      cond do
        ctx.platform_anchors != [] and roll < 0.08 ->
          ctx.platform_anchors |> Enum.random() |> jitter_around(@anchor_jitter_m) |> keep_out_center()

        ctx.gather_anchors != [] and roll < 0.58 ->
          ctx.gather_anchors
          |> Enum.random()
          |> jitter_around(@group_join_jitter_m)
          |> clamp_point(usable)
          |> outside_platform(ctx.platform_r)

        true ->
          random_point_in_disk(usable * 0.7)
      end

    factor = ctx.factor
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

  # Gathering spots for standing groups, scattered in the ring between just
  # outside the platform edge and close to the world rim. The radius uses sqrt
  # sampling (area-uniform) so anchors lean toward the outer ring instead of
  # hugging the platform — most standing groups end up out near the edge.
  defp gen_gather_anchors(platform_r, world_r, n) do
    inner = platform_r + 1.0
    outer = max(world_r - @edge_margin_m - 0.2, inner + 0.1)

    for _ <- 1..n do
      theta = 2.0 * :math.pi() * :rand.uniform()
      r = inner + :math.sqrt(:rand.uniform()) * (outer - inner)
      %{x: r * :math.cos(theta), y: r * :math.sin(theta)}
    end
  end

  # Count of people in `behavior` within `@group_radius_m` of each anchor, as a
  # list aligned with the anchor list by index. Used both for platform loungers
  # (`:lounging`) and off-platform standing groups (`:grouping`).
  defp occupancy(people, anchors, behavior) do
    matching = Enum.filter(people, &(&1.behavior == behavior))

    Enum.map(anchors, fn a ->
      Enum.count(matching, fn p -> sq(p.x - a.x) + sq(p.y - a.y) <= sq(@group_radius_m) end)
    end)
  end

  # Pick an anchor to join: prefer one that already has a small group (so
  # clusters form), otherwise take a free one. Anchors at `cap` are skipped; if
  # all are full, return nil (caller roams instead).
  defp choose_anchor([], _occ, _cap), do: nil

  defp choose_anchor(anchors, occ, cap) do
    indexed = Enum.with_index(anchors)
    joinable = Enum.filter(indexed, fn {_a, i} -> c = Enum.at(occ, i); c > 0 and c < cap end)
    empty = Enum.filter(indexed, fn {_a, i} -> Enum.at(occ, i) == 0 end)

    cond do
      joinable != [] and :rand.uniform() < 0.7 -> joinable |> Enum.random() |> elem(0)
      joinable ++ empty != [] -> (joinable ++ empty) |> Enum.random() |> elem(0)
      true -> nil
    end
  end

  # Nearest anchor within `max_dist` of the person, or nil. Gives grouping people
  # "stickiness": once parked near a spot they keep shuffling there instead of
  # picking a fresh anchor each retarget.
  defp nearest_anchor(_person, [], _max_dist), do: nil

  defp nearest_anchor(person, anchors, max_dist) do
    {anchor, d2} =
      anchors
      |> Enum.map(fn a -> {a, sq(person.x - a.x) + sq(person.y - a.y)} end)
      |> Enum.min_by(fn {_a, d2} -> d2 end)

    if d2 <= sq(max_dist), do: anchor, else: nil
  end

  # Push a point radially out so it sits just outside the platform edge, keeping
  # standing groups out of the chill zone.
  defp outside_platform({x, y}, platform_r) do
    target = platform_r + @platform_margin_m
    dist = :math.sqrt(x * x + y * y)

    cond do
      dist >= target -> {x, y}
      dist > 0.0 -> {x * target / dist, y * target / dist}
      true -> {target, 0.0}
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
