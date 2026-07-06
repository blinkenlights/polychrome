defmodule Octopus.Apps.Rain do
  use Octopus.App, category: :interactive

  alias Octopus.Installation
  alias Octopus.Canvas
  alias Octopus.Particles
  alias Octopus.Radar
  alias Octopus.Radar.Frame
  alias Octopus.Radar.PanelMapping

  def name, do: "⛈️ Rain"

  def compatible?() do
    installation_info = Octopus.App.get_installation_info()

    installation_info.panel_width >= 8 and
      installation_info.panel_height >= 8
  end

  defmodule State do
    defstruct [
      :panels,
      :last_tick,
      :lightning,
      :track_registry,
      :last_splash,
      :last_lightning,
      :track_motion
    ]
  end

  @fps 60
  @frame_time_ms trunc(1000 / @fps)
  @rain_color_1 {100, 180, 255}
  @rain_color_2 {70, 130, 169}
  @rain_color_3 {145, 200, 228}
  @rain_color_4 {137, 138, 196}
  @rain_color_5 {192, 201, 238}
  @rain_color_6 {116, 155, 194}
  @splash_color {133, 183, 212}
  @proximity_splash_color {255, 0, 255}

  # Panel ring band (m): people near the display ring.
  @ring_inner_m 4.0
  @ring_outer_m 10.0
  @splash_cooldown_ms 350
  @track_stale_ms 500

  # Lightning: ring entry and/or speed spike, per-person cooldown.
  @lightning_speed_spike 0.5
  @lightning_cooldown_ms 1_200

  def app_init(_args) do
    Octopus.App.configure_display(layout: :adjacent_panels)
    Radar.subscribe()

    panel_count = Installation.num_panels()
    panel_width = Installation.panel_width()
    panel_height = Installation.panel_height()

    panels =
      for i <- 0..(panel_count - 1), into: %{} do
        drops = new_rain_system(panel_width, panel_height)
        splash = new_splash_system(panel_width, panel_height)
        proximity_splash = new_proximity_splash_system(panel_width, panel_height)
        {i, {drops, splash, proximity_splash}}
      end

    state = %State{
      panels: panels,
      last_tick: System.monotonic_time(:millisecond),
      lightning: [],
      track_registry: %{},
      last_splash: %{},
      last_lightning: %{},
      track_motion: %{}
    }
    :timer.send_interval(@frame_time_ms, :tick)
    {:ok, state}
  end

  def handle_info({:radar_frame, _device_id, %Frame{tracks: tracks}}, state) do
    now = :erlang.monotonic_time(:millisecond)

    track_registry =
      Enum.reduce(tracks, state.track_registry, fn track, acc ->
        person = %{
          id: track.id,
          x: track.x,
          y: track.y,
          vx: track.vx,
          vy: track.vy
        }

        Map.put(acc, track.id, {person, now})
      end)

    {:noreply, %{state | track_registry: track_registry}}
  end

  def handle_info(
        :tick,
        %State{panels: panels, last_tick: last_tick, lightning: lightning, track_registry: track_registry} =
          state
      ) do
    now = System.monotonic_time(:millisecond)
    dt = max((now - last_tick) / 1000, 0.001)
    radar_now = :erlang.monotonic_time(:millisecond)

    people = active_people(track_registry, radar_now, @track_stale_ms)

    panel_count = Installation.num_panels()
    panel_width = Installation.panel_width()
    panel_height = Installation.panel_height()

    {panels, last_splash} =
      apply_radar_splashes(
        people,
        panels,
        state.last_splash,
        now,
        panel_count,
        panel_width,
        panel_height
      )

    {lightning, last_lightning, track_motion} =
      spawn_radar_lightning(
        people,
        lightning,
        state.last_lightning,
        state.track_motion,
        now,
        panel_count,
        panel_width
      )

    lightning =
      lightning
      |> Enum.map(fn l -> %{l | ttl: l.ttl - 1} end)
      |> Enum.filter(fn l -> l.ttl > 0 end)

    panels =
      panels
      |> Enum.map(fn {i, {drops, splash, proximity_splash}} ->
        drops = maybe_spawn_rain(drops)
        drops = Particles.update(drops, dt)
        splash = maybe_splash(drops, splash)
        splash = Particles.update(splash, dt)
        proximity_splash = Particles.update(proximity_splash, dt)
        {i, {drops, splash, proximity_splash}}
      end)
      |> Enum.into(%{})

    big_canvas = Canvas.new(panel_count * panel_width, panel_height)

    big_canvas =
      Enum.reduce(panels, big_canvas, fn {i, {drops, splash, proximity_splash}}, acc ->
        drops_canvas = Particles.draw(drops, Canvas.new(panel_width, panel_height))
        splash_canvas = Particles.draw(splash, Canvas.new(panel_width, panel_height))
        prox_canvas = Particles.draw(proximity_splash, Canvas.new(panel_width, panel_height))

        acc
        |> Canvas.overlay(drops_canvas, offset: {i * panel_width, 0})
        |> Canvas.overlay(splash_canvas, offset: {i * panel_width, 0})
        |> Canvas.overlay(prox_canvas, offset: {i * panel_width, 0})
      end)

    big_canvas = draw_lightning(big_canvas, lightning, panel_width, panel_height)

    Octopus.App.update_display(big_canvas)

    {:noreply,
     %{
       state
       | panels: panels,
         last_tick: now,
         lightning: lightning,
         last_splash: last_splash,
         last_lightning: last_lightning,
         track_motion: track_motion
     }}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp active_people(track_registry, now, stale_ms) do
    track_registry
    |> Enum.filter(fn {_id, {_person, seen_at}} -> now - seen_at <= stale_ms end)
    |> Enum.map(fn {_id, {person, _seen_at}} -> person end)
  end

  defp apply_radar_splashes(people, panels, last_splash, now, panel_count, panel_width, panel_height) do
    Enum.reduce(people, {panels, last_splash}, fn person, {panels_acc, splash_acc} ->
      if PanelMapping.in_ring?(person, @ring_inner_m, @ring_outer_m) do
        {panel_index, x, radius} =
          PanelMapping.track_to_splash_pos(person, panel_count, panel_width)

        splash_key = {person.id, panel_index}

        if recently_splashed?(splash_acc, splash_key, now) do
          {panels_acc, splash_acc}
        else
          speed = PanelMapping.track_speed(person)
          {count, min_speed, max_speed} = splash_intensity(radius, speed)

          {drops, splash, proximity_splash} = Map.fetch!(panels_acc, panel_index)

          proximity_splash =
            Particles.spawn(proximity_splash, {x, panel_height - 1}, count,
              min_speed: min_speed,
              max_speed: max_speed
            )

          panels_acc = Map.put(panels_acc, panel_index, {drops, splash, proximity_splash})
          splash_acc = Map.put(splash_acc, splash_key, now)
          {panels_acc, splash_acc}
        end
      else
        {panels_acc, splash_acc}
      end
    end)
  end

  defp recently_splashed?(last_splash, key, now) do
    case Map.get(last_splash, key) do
      nil -> false
      ts -> now - ts < @splash_cooldown_ms
    end
  end

  defp splash_intensity(radius, speed) do
    radial =
      1.0 - (radius - @ring_inner_m) / (@ring_outer_m - @ring_inner_m)
      |> clamp01()

    count = trunc(2 + radial * 4 + speed * 2) |> max(2) |> min(10)
    base = 14 + radial * 10 + speed * 14
    {count, base, base + 16}
  end

  defp spawn_radar_lightning(people, lightning, last_lightning, track_motion, now, panel_count, panel_width) do
    active_ids = MapSet.new(Enum.map(people, & &1.id))

    {lightning, last_lightning, track_motion} =
      Enum.reduce(people, {lightning, last_lightning, track_motion}, fn person,
                                                                         {bolts_acc, cooldown_acc,
                                                                          motion_acc} ->
        speed = PanelMapping.track_speed(person)
        in_ring = PanelMapping.in_ring?(person, @ring_inner_m, @ring_outer_m)
        prev = Map.get(motion_acc, person.id, %{speed: speed, in_ring: in_ring})

        ring_entry = in_ring and not prev.in_ring
        speed_spike = speed - prev.speed >= @lightning_speed_spike

        motion_acc = Map.put(motion_acc, person.id, %{speed: speed, in_ring: in_ring})

        cond do
          not ring_entry and not speed_spike ->
            {bolts_acc, cooldown_acc, motion_acc}

          recently_lit?(cooldown_acc, person.id, now) ->
            {bolts_acc, cooldown_acc, motion_acc}

          true ->
            {panel_index, _x, _} =
              PanelMapping.track_to_splash_pos(person, panel_count, panel_width)

            bolt = %{panel: panel_index, x: div(panel_width, 2), ttl: 16}
            cooldown_acc = Map.put(cooldown_acc, person.id, now)
            {[bolt | bolts_acc], cooldown_acc, motion_acc}
        end
      end)

    track_motion = Map.take(track_motion, MapSet.to_list(active_ids))

    {lightning, last_lightning, track_motion}
  end

  defp recently_lit?(last_lightning, track_id, now) do
    case Map.get(last_lightning, track_id) do
      nil -> false
      ts -> now - ts < @lightning_cooldown_ms
    end
  end

  defp clamp01(value), do: value |> max(0.0) |> min(1.0)

  defp new_rain_system(width, height) do
    Particles.new(
      width,
      height,
      :math.pi() / 2,
      0.05,
      rain_color(),
      0.5,
      1.2,
      18,
      28
    )
  end

  defp new_splash_system(width, height) do
    Particles.new(
      width,
      height,
      :math.pi() / 2,
      0.05,
      [@splash_color],
      0.5,
      1.2,
      18,
      28
    )
  end

  defp new_proximity_splash_system(width, height) do
    Particles.new(
      width,
      height,
      :math.pi() * 1.5,
      0.45,
      [@splash_color, @proximity_splash_color],
      0.8,
      1.4,
      18,
      32
    )
  end

  defp maybe_spawn_rain(sys) do
    if :rand.uniform() < 0.3 do
      x = :rand.uniform() * (sys.width - 1)
      Particles.spawn(sys, {x, 0}, 1, colors: rain_color())
    else
      sys
    end
  end

  defp rain_color() do
    Enum.random([
      @rain_color_1,
      @rain_color_2,
      @rain_color_3,
      @rain_color_4,
      @rain_color_5,
      @rain_color_6
    ])
  end

  defp maybe_splash(drops, splash) do
    splash_particles =
      drops.particles
      |> Enum.filter(fn p -> p.y > drops.height - 1 end)
      |> Enum.filter(fn _ -> :rand.uniform() < 0.08 end)

    Enum.reduce(splash_particles, splash, fn p, acc ->
      Particles.spawn(acc, {p.x, acc.height}, 1,
        angle: :math.pi() * 1.5,
        spread: 0.3,
        min_ttl: 0.2,
        max_ttl: 0.5,
        min_speed: 10,
        max_speed: 20
      )
    end)
  end

  defp draw_lightning(canvas, lightning, panel_width, panel_height) do
    Enum.reduce(lightning, canvas, fn l, acc ->
      flash_canvas(canvas)
      x = l.panel * panel_width + l.x

      {_, path} =
        Enum.reduce(0..(panel_height - 1), {x, []}, fn y, {cur_x, acc_path} ->
          dx = Enum.random([-1, 0, 1])
          next_x = min(max(cur_x + dx, l.panel * panel_width), (l.panel + 1) * panel_width - 1)
          {next_x, [{next_x, y} | acc_path]}
        end)

      Enum.reduce(path, acc, fn {px, py}, c ->
        Canvas.put_pixel(c, {px, py}, {255, 241, 23})
      end)
    end)
  end

  defp flash_canvas(canvas) do
    Canvas.fill(canvas, {247, 242, 200})
  end
end
