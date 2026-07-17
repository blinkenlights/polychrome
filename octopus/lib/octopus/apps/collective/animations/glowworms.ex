defmodule Octopus.Apps.Collective.Animations.Glowworms do
  @moduledoc """
  A Glowworm is a bright dot with a corona of 1 px width surounded
  This ASCII Art scribbles the idea. The glowworm should be animated as if would use wings,
  shown in the ASCII art the top and the bottom dots are changing brightness.
  wings move up and down and up again within a period of 0.5 seconds (adjusted when traveling).
  a wing move is simulated by changing brightness, when wings are up, the upper pixel is brighter then the bottom one, and vice versa when the wings are down
  the 'o' in the ASCII art is the brightest pixel in the middle.
  ```
   .
  .o.
   .
  ```

  The life and behavior of glowworms are described with thw following rules:
  - Glowworms have their own characters, which means lifetime attributes
  - when a glowworm is initialized (means born), an individual color is chosen, from a pallette of light yellow, light orange, light red, light green, no blue;
      - use very pastel colors only
      - colors don't change and a glowworms keeps the color until it dies
      - the color intensity (means if its more white or more pastel color) is configurable via web view
      - every glowworm has an age, which is the number of seconds since birth
      - when glowworm dies, it fades to black within a second, and it's character is purged
  - flight trajectories of glowworms is more horizonal, with little variations up and down
      - glowworms never leave the world, means they only fly on pixels visible in the world
  - theres a global maximum, only 10 glowworms can exist at a time (with some exceptions when new glowworms are born, see details below)
      - the number of max glowworms is configurable via web view
  - every glowworm lifes in iterating phases
      - there's a "stay phase" in which the worm remains for 5-10 seconds (random value in between) and only moves in smaller circles of 3-5 pixels area;
        the circling area is configurable via slider in a web view
      - there's a traveling phase in which at which the worm picks a target location in the world and sets a route to it and starts moving towards that position;
        a flight is not strictly straight but somehow wobbling and the wings are moving
      - when during the traveling phase w worm meets another worm within a 3px area, then both need to make a decision if they want to stop traveling and switch to stay phase;
        each worm makes an individual decision with a 50/50 chance to stay, only when both conclude to stay, the stop the travel, else they continue their travel;
        the chance to stay should be configurable per web view
  - when for longer than 5 seconds (configurable via web view), more than 3 (configurable via web view) worms are in proximity of 5px (configurable via web view),
    then they decide to run away; run away means they pick a random target and start fast flying into their individual target, this means they switch into travel phase,
    but with a special thing that they have a higher speed to run away from each other in the beginning of the run away and then slow down until reaching their target position,
    this should look like a bit a of explosion of glowworms, and means curved trajectories towards the target should be seen

  - when there are gravitation objects sensed and available, all glowworms consider within 1-3 random seconds, to start flying towards the strongest gravity
    - when multiple gravitation points with the same value are present, each glowworm picks its own target
    - the center of the gravity is used as an unsharp target for worms, which means when the decide to fly towards the gravity they pick a target slightly off (3px-5px) the actual center of gravity
    - when a worm decides to fly towards gravity, it increases its movement speed by 10% to 50% for that journey, correlating linearly to the gravity value (10% at <= 0.3 gravity, 50% at 1.0 gravity)
    - when they reached the center of gravity, they switch to stay phase for ca. 3x (with little randomness, and configurable via web view) longer time than usual, bevor they iterate towards travel phase

  - when two glowworms are longer than 30seconds (configurable via web view) within a radius of 2px to 4px a new glowworm is born
  - as a global rule, when for more than 45s (configurable via web view) there are more glowworms on the world than the maximum value allows, the oldest glowrom dies
  - just in case the overall population grows beyond 20, no more glowworms can be born

  Authored for a 12-panel (96 px wide) × 8 px ring;
  """

  @behaviour Octopus.Apps.Collective.Animation

  alias Octopus.Canvas
  alias Octopus.Radar

  @width 96
  @height 8

  @palettes [
    {1.0, 1.0, 0.6}, # light yellow
    {1.0, 0.8, 0.6}, # light orange
    {1.0, 0.6, 0.6}, # light red
    {0.6, 1.0, 0.6}  # light green
  ]

  defmodule Worm do
    defstruct [
      :id,
      :x,
      :y,
      :vx,
      :vy,
      :target_x,
      :target_y,
      :color,
      :age,
      :phase,
      :phase_timer,
      :wings_t,
      :proximity_timer,
      :birth_timer,
      :gravity_timer,
      :stay_duration_multiplier,
      :dead_timer,
      travel_speed_multiplier: 1.0,
      fast?: 0.0,
      spawn_baby?: false
    ]
  end

  @impl true
  def name, do: "Glowworms"

  @impl true
  def init(_display_info) do
    %{
      worms: [],
      next_id: 1,
      overpopulation_timer: 0.0
    }
  end

  @impl true
  def render(%Canvas{} = canvas, _people, ctx, state) do
    dt = ctx.dt |> min(0.1)

    # Configuration
    max_count = Map.get(ctx, :glowworms_max_count, 10)
    color_intensity = Map.get(ctx, :glowworms_color_intensity, 0.8)
    overpopulation_death_duration = Map.get(ctx, :glowworms_overpopulation_death_duration, 45)

    # 1. Spawning
    state = spawn_worms(state, max_count, ctx)

    # 2. Update logic
    state = update_worms(state, dt, ctx)

    # 3. Overpopulation management
    state = handle_overpopulation(state, dt, max_count, overpopulation_death_duration)

    # 4. Rendering
    pixels = render_worms(canvas.width, canvas.height, state.worms, color_intensity)

    {%Canvas{canvas | pixels: pixels}, state}
  end

  defp spawn_worms(state, max_count, ctx) do
    if length(state.worms) < max_count and length(state.worms) < 20 do
      # Chance to spawn if under max
      if :rand.uniform() < 0.05 do
        speed_multiplier = Map.get(ctx, :glowworms_speed, 1.0)
        new_worm = %Worm{
          id: state.next_id,
          x: :rand.uniform() * @width,
          y: :rand.uniform() * @height,
          vx: (:rand.uniform() - 0.5) * 2.0 * speed_multiplier,
          vy: (:rand.uniform() - 0.5) * 0.5 * speed_multiplier,
          color: Enum.random(@palettes),
          age: 0.0,
          phase: :stay,
          phase_timer: :rand.uniform(5) + 5.0,
          wings_t: :rand.uniform() * 0.5,
          proximity_timer: 0.0,
          birth_timer: 0.0,
          gravity_timer: :rand.uniform() * 2.0 + 1.0,
          stay_duration_multiplier: 1.0,
          travel_speed_multiplier: 1.0,
          fast?: 0.0
        }

        %{state | worms: state.worms ++ [new_worm], next_id: state.next_id + 1}
      else
        state
      end
    else
      state
    end
  end

  defp update_worms(state, dt, ctx) do
    speed_multiplier = Map.get(ctx, :glowworms_speed, 1.0)
    circling_area = Map.get(ctx, :glowworms_circling_area, 4)
    stay_chance = Map.get(ctx, :glowworms_stay_chance, 0.5)
    run_away_proximity = Map.get(ctx, :glowworms_run_away_proximity, 5)
    run_away_count = Map.get(ctx, :glowworms_run_away_count, 3)
    run_away_duration = Map.get(ctx, :glowworms_run_away_duration, 5)
    gravity_stay_multiplier = Map.get(ctx, :glowworms_gravity_stay_multiplier, 3.0)
    birth_proximity_duration = Map.get(ctx, :glowworms_birth_proximity_duration, 30)

    gravity_info = Radar.panel_gravity()

    # Process existing worms
    {updated_worms, newborns} =
      state.worms
      |> Enum.reduce({[], []}, fn worm, {acc_updated, acc_newborns} ->
        updated =
          worm
          |> update_worm_age_and_wings(dt, speed_multiplier)
          |> handle_worm_phase(dt, circling_area, gravity_info, gravity_stay_multiplier, speed_multiplier)
          |> handle_worm_proximity(state.worms, dt, run_away_proximity, run_away_count, run_away_duration, speed_multiplier)
          |> handle_worm_meetings(state.worms, dt, stay_chance)
          |> handle_worm_birth_proximity(state.worms, dt, birth_proximity_duration)
          |> move_worm(dt)

        if Map.get(updated, :spawn_baby?, false) do
          # Mark parent as no longer spawning, but we'll collect the baby request
          {acc_updated ++ [%{updated | spawn_baby?: false}], acc_newborns ++ [updated]}
        else
          {acc_updated ++ [updated], acc_newborns}
        end
      end)

    # Spawn babies
    {final_worms, next_id} = spawn_babies(updated_worms, newborns, state.next_id, speed_multiplier)

    # Clean up purged worms
    final_worms = Enum.reject(final_worms, fn worm -> worm.phase == :purged end)

    %{state | worms: final_worms, next_id: next_id}
  end

  defp spawn_babies(worms, [], next_id, _speed_multiplier), do: {worms, next_id}
  defp spawn_babies(worms, newborns, next_id, speed_multiplier) do
    if length(worms) >= 20 do
      {worms, next_id}
    else
      # To avoid too many babies, we just spawn one per frame if multiple parents are ready
      parent = hd(newborns)
      baby = %Worm{
        id: next_id,
        x: parent.x,
        y: parent.y,
        vx: (:rand.uniform() - 0.5) * 2.0 * speed_multiplier,
        vy: (:rand.uniform() - 0.5) * 0.5 * speed_multiplier,
        color: Enum.random(@palettes),
        age: 0.0,
        phase: :stay,
        phase_timer: :rand.uniform(5) + 5.0,
        wings_t: :rand.uniform() * 0.5,
        proximity_timer: 0.0,
        birth_timer: 0.0,
        gravity_timer: :rand.uniform() * 2.0 + 1.0,
        stay_duration_multiplier: 1.0,
        travel_speed_multiplier: 1.0,
        fast?: 0.0
      }
      {worms ++ [baby], next_id + 1}
    end
  end

  defp update_worm_age_and_wings(worm, dt, speed_multiplier) do
    speed_factor =
      if worm.phase == :travel do
        base = worm.travel_speed_multiplier || 1.0

        if worm.fast? > 0 do
          base + worm.fast? / (2.0 * speed_multiplier)
        else
          base
        end
      else
        1.0
      end

    %{
      worm
      | age: worm.age + dt,
        wings_t: :math.fmod(worm.wings_t + dt * speed_factor, 0.5)
    }
  end

  defp handle_worm_phase(worm, dt, circling_area, gravity_info, gravity_stay_multiplier, speed_multiplier) do
    cond do
      worm.phase == :dying ->
        timer = (worm.dead_timer || 1.0) - dt
        if timer <= 0, do: %{worm | phase: :purged}, else: %{worm | dead_timer: timer}

      true ->
        # Gravity check for both stay and travel phases
        {worm, vx, vy} = check_gravity(worm, dt, gravity_info, gravity_stay_multiplier, speed_multiplier, worm.vx, worm.vy)
        worm = %{worm | vx: vx, vy: vy}

        case worm.phase do
          :stay ->
            if worm.phase_timer <= 0 do
              # Switch to travel
              target_x = :rand.uniform() * @width
              target_y = :rand.uniform() * @height
              travel_speed_multiplier = :rand.uniform() * 0.5 + 0.75

              %{
                worm
                | phase: :travel,
                  target_x: target_x,
                  target_y: target_y,
                  phase_timer: 0.0,
                  travel_speed_multiplier: travel_speed_multiplier,
                  fast?: 0.0
              }
            else
              # Stay logic: small random movement within circling area
              # We'll just use a small random force and damping
              vx = worm.vx + (:rand.uniform() - 0.5) * 0.5 * speed_multiplier
              vy = worm.vy + (:rand.uniform() - 0.5) * 0.2 * speed_multiplier
              # Keep speed low in stay phase
              speed_sq = vx * vx + vy * vy
              max_stay_speed = circling_area * 0.2 * speed_multiplier
              {vx, vy} = if speed_sq > max_stay_speed * max_stay_speed do
                f = max_stay_speed / :math.sqrt(speed_sq)
                {vx * f, vy * f}
              else
                {vx, vy}
              end

              %{worm | vx: vx * 0.9, vy: vy * 0.9, phase_timer: worm.phase_timer - dt}
            end

          :travel ->
            # Traveling logic
            dx = angular_diff(worm.target_x, worm.x, @width)
            dy = worm.target_y - worm.y
            dist = :math.sqrt(dx * dx + dy * dy)

            if dist < 1.0 do
              # Reached target
              %{worm | phase: :stay, phase_timer: (:rand.uniform(5) + 5.0) * worm.stay_duration_multiplier, stay_duration_multiplier: 1.0, vx: 0.0, vy: 0.0, fast?: 0.0}
            else
              # Move towards target with wobbling and deceleration
              base_speed = 2.0 * speed_multiplier * (worm.travel_speed_multiplier || 1.0)
              current_speed = if worm.fast? > 0, do: base_speed + worm.fast?, else: base_speed

              vx = (dx / dist) * current_speed + (:rand.uniform() - 0.5) * 0.8 * speed_multiplier * (worm.travel_speed_multiplier || 1.0) # wobbling
              vy = (dy / dist) * (current_speed * 0.2) + (:rand.uniform() - 0.5) * 0.3 * speed_multiplier * (worm.travel_speed_multiplier || 1.0) # more horizontal

              # Decelerate if running away
              new_fast = if worm.fast? > 0, do: max(0.0, worm.fast? - dt * 2.0), else: 0.0

              %{worm | vx: vx, vy: vy, fast?: new_fast}
            end

          _ ->
            worm
        end
    end
  end

  defp check_gravity(worm, dt, gravity_info, gravity_stay_multiplier, speed_multiplier, vx, vy) do
    if gravity_info.gravity != %{} and worm.gravity_timer <= 0 do
      max_val = Map.values(gravity_info.gravity) |> Enum.max()

      if max_val > 0.05 do
        best_panels =
          gravity_info.gravity
          |> Enum.filter(fn {_, v} -> v == max_val end)
          |> Enum.map(fn {p, _} -> p end)

        target_panel = Enum.random(best_panels)
        offset = (if :rand.uniform() > 0.5, do: 1, else: -1) * (3 + :rand.uniform() * 2)
        target_x = :math.fmod(target_panel * 8 + 3.5 + offset + @width, @width)
        target_y = :rand.uniform() * @height

        # Check if we are already staying near this gravity target
        already_at_gravity? = worm.phase == :stay and abs(angular_diff(target_x, worm.x, @width)) < 5.0

        if already_at_gravity? do
          {%{worm | gravity_timer: :rand.uniform() * 2.0 + 1.0}, vx, vy}
        else
          boost =
            cond do
              max_val <= 0.3 -> 0.1
              max_val >= 1.0 -> 0.5
              true -> 0.1 + (max_val - 0.3) * 0.4 / 0.7
            end

          gravity_multiplier = 1.0 + boost
          travel_speed_multiplier = (:rand.uniform() * 0.5 + 0.75) * gravity_multiplier

          new_worm = %{
            worm
            | phase: :travel,
              target_x: target_x,
              target_y: target_y,
              gravity_timer: :rand.uniform() * 2.0 + 1.0,
              stay_duration_multiplier: gravity_stay_multiplier,
              travel_speed_multiplier: travel_speed_multiplier,
              fast?: 0.0
          }

          # Update velocity towards new target immediately
          dx = angular_diff(new_worm.target_x, new_worm.x, @width)
          dy = new_worm.target_y - new_worm.y
          dist = :math.sqrt(dx * dx + dy * dy)

          if dist > 0.1 do
            speed = 2.0 * speed_multiplier * new_worm.travel_speed_multiplier
            {new_worm, (dx / dist) * speed, (dy / dist) * speed * 0.2}
          else
            {new_worm, vx, vy}
          end
        end
      else
        {%{worm | gravity_timer: :rand.uniform() * 2.0 + 1.0}, vx, vy}
      end
    else
      {%{worm | gravity_timer: worm.gravity_timer - dt}, vx, vy}
    end
  end

  defp move_worm(worm, dt) do
    new_x = :math.fmod(worm.x + worm.vx * dt + @width, @width)
    new_y = worm.y + worm.vy * dt

    # Keep in world (Y bounce)
    {new_y, vy} =
      cond do
        new_y < 0 -> {0.0, abs(worm.vy) * 0.5}
        new_y > @height - 1 -> {@height - 1.0, -abs(worm.vy) * 0.5}
        true -> {new_y, worm.vy}
      end

    %{worm | x: new_x, y: new_y, vy: vy}
  end

  defp handle_worm_proximity(worm, all_worms, dt, run_away_proximity, run_away_count, run_away_duration, speed_multiplier) do
    # Bounding box check for proximity
    others_count =
      all_worms
      |> Enum.filter(fn other ->
        other.id != worm.id and
          abs(angular_diff(other.x, worm.x, @width)) <= run_away_proximity and
          abs(other.y - worm.y) <= run_away_proximity
      end)
      |> length()

    if others_count >= run_away_count do
      timer = worm.proximity_timer + dt
      if timer >= run_away_duration do
        # Run away!
        target_x = :math.fmod(worm.x + (if :rand.uniform() > 0.5, do: 1, else: -1) * (15 + :rand.uniform() * 20) + @width, @width)
        target_y = :rand.uniform() * @height
        travel_speed_multiplier = :rand.uniform() * 0.5 + 0.75

        %{
          worm
          | phase: :travel,
            target_x: target_x,
            target_y: target_y,
            proximity_timer: 0.0,
            travel_speed_multiplier: travel_speed_multiplier,
            fast?: 3.0 * speed_multiplier * travel_speed_multiplier
        }
      else
        %{worm | proximity_timer: timer}
      end
    else
      %{worm | proximity_timer: max(0.0, worm.proximity_timer - dt)}
    end
  end

  defp handle_worm_meetings(worm, all_worms, _dt, stay_chance) do
    if worm.phase == :travel and worm.fast? == 0.0 do
      # Check for other travelers nearby
      nearby_traveler =
        all_worms
        |> Enum.find(fn other ->
          other.id != worm.id and other.phase == :travel and
            abs(angular_diff(other.x, worm.x, @width)) <= 3 and
            abs(other.y - worm.y) <= 3
        end)

      if nearby_traveler do
        # Both make decision
        if :rand.uniform() < stay_chance and :rand.uniform() < stay_chance do
           %{worm | phase: :stay, phase_timer: :rand.uniform(5) + 5.0}
        else
          worm
        end
      else
        worm
      end
    else
      worm
    end
  end

  defp handle_worm_birth_proximity(worm, all_worms, dt, birth_proximity_duration) do
    nearby =
      all_worms
      |> Enum.find(fn other ->
        other.id != worm.id and
          abs(angular_diff(other.x, worm.x, @width)) >= 2 and
          abs(angular_diff(other.x, worm.x, @width)) <= 4 and
          abs(other.y - worm.y) >= 2 and
          abs(other.y - worm.y) <= 4
      end)

    if nearby do
      timer = worm.birth_timer + dt
      if timer >= birth_proximity_duration do
        %{worm | birth_timer: -100.0, spawn_baby?: true} # Mark for birth, big negative to prevent immediate refire
      else
        %{worm | birth_timer: timer}
      end
    else
      %{worm | birth_timer: max(0.0, worm.birth_timer - dt)}
    end
  end

  defp handle_overpopulation(state, dt, max_count, death_duration) do
    if length(state.worms) > max_count do
      timer = state.overpopulation_timer + dt
      if timer >= death_duration do
        # Oldest dies
        oldest = state.worms |> Enum.min_by(fn w -> w.age end, fn -> nil end)
        worms =
          if oldest do
            state.worms |> Enum.map(fn w -> if w.id == oldest.id, do: %{w | phase: :dying, dead_timer: 1.0}, else: w end)
          else
            state.worms
          end
        %{state | worms: worms, overpopulation_timer: 0.0}
      else
        %{state | overpopulation_timer: timer}
      end
    else
      %{state | overpopulation_timer: 0.0}
    end
  end

  defp render_worms(width, height, worms, intensity) do
    for worm <- worms, worm.phase != :purged, reduce: %{} do
      acc ->
        draw_worm(acc, worm, width, height, intensity)
    end
  end

  defp draw_worm(pixels, worm, width, height, intensity) do
    # Pastel color
    {pr, pg, pb} = worm.color
    # Blend with white
    r = (1.0 - intensity) + pr * intensity
    g = (1.0 - intensity) + pg * intensity
    b = (1.0 - intensity) + pb * intensity

    # Fade if dying
    fade = if worm.phase == :dying, do: worm.dead_timer, else: 1.0
    {r, g, b} = {r * fade, g * fade, b * fade}

    # Wing animation
    # wings move up/down every 0.5s. Sudden transition.
    # 0-0.25s: up, 0.25-0.5s: down
    wings_up? = worm.wings_t < 0.25

    # Pattern:
    #  .
    # .o.
    #  .
    points = [
      {0, 0, 1.0},   # center
      {1, 0, 0.5},   # right
      {-1, 0, 0.5},  # left
      {0, 1, if(wings_up?, do: 0.3, else: 0.7)}, # bottom
      {0, -1, if(wings_up?, do: 0.7, else: 0.3)} # top
    ]

    Enum.reduce(points, pixels, fn {dx, dy, brightness}, acc ->
      px = Integer.mod(round(worm.x) + dx, width)
      py = round(worm.y) + dy
      if py >= 0 and py < height do
        color = {round(r * brightness * 255), round(g * brightness * 255), round(b * brightness * 255)}
        Map.update(acc, {px, py}, color, fn existing -> blend(existing, color) end)
      else
        acc
      end
    end)
  end

  defp blend({r1, g1, b1}, {r2, g2, b2}) do
    {min(255, r1 + r2), min(255, g1 + g2), min(255, b1 + b2)}
  end

  defp angular_diff(x1, x2, width) do
    d = x1 - x2
    cond do
      d > width / 2 -> d - width
      d < -width / 2 -> d + width
      true -> d
    end
  end
end
