defmodule OctopusWeb.RadarLive do
  @moduledoc """
  Live visualization of the HLK-LD6001A-60G radar layer.

  Subscribes to the global radar topic and renders detections as a single
  top-down SVG drawn in the installation global frame. The same canvas shows
  the sensor placements and their coverage; in mock mode it additionally
  draws the simulated world border and the ground-truth people, so the
  operator can see at a glance how well each sensor's detections agree with
  reality.

  A feature legend lets the operator toggle individual visual layers
  (velocity arrows, trails, height-as-size, ground-truth, …) on and off.
  All state and rendering live on the server; LiveView's diffing pushes the
  per-frame attribute updates over WebSocket.
  """

  use OctopusWeb, :live_view

  alias Octopus.Installation
  alias Octopus.Radar
  alias Octopus.Radar.{Frame, Track}
  alias Octopus.Radar.Mock.World

  # 10 s rolling window used both for the displayed min/max and for
  # deriving per-id trails.
  @window_ms 10_000
  # How long a track keeps being drawn after its last sighting (used for
  # the fade-out animation).
  @fade_ms 1_000
  # How far back the per-id trail extends.
  @trail_ms 4_000

  # Minimum time the "max people applying" spinner stays visible, so the
  # feedback is noticeable even when the population reaches the cap quickly.
  @apply_min_ms 700

  # Lightness range for the trail's per-segment color. The newest
  # segment (closest to the body circle) is rendered at `@trail_l_near`
  # and brightens linearly toward `@trail_l_far` for the oldest segment.
  @trail_l_near 60
  @trail_l_far 95

  # SVG viewBox extent. The template hardcodes the matching string. The
  # layout uses an `aspect-square` container so circles always render
  # circular regardless of the X/Y data ranges.
  @vb 1000

  # z (meters) range mapped onto the circle radius range (in viewBox
  # units). Targets below 0 m or above 2.5 m clamp to the endpoints.
  @z_min 0.0
  @z_max 2.5
  @r_min 18
  @r_max 72

  # Detection radius used when "height-as-size" is toggled off.
  @detection_fixed_r 28

  # Ground-truth person marker radius and sensor placement marker half-side.
  @ground_truth_r 12
  @sensor_marker_half 26

  # Velocity (m/s) → viewBox-unit scale for the velocity arrow.
  @velocity_scale 40
  @velocity_max_len 100

  # Fixed palette of well-separated hues. Saturation and lightness are
  # shared across all sensors so the only dimension that varies between
  # sensors is hue, giving the strongest cross-sensor distinguishability.
  @hues [0, 36, 72, 108, 144, 180, 216, 252, 288, 324]
  @body_saturation 70
  @body_lightness 75
  @sensor_detecting_saturation 100
  @sensor_detecting_lightness 82

  # Padding (in meters) added around the data to avoid divide-by-zero
  # when the window is empty or all samples coincide.
  @minmax_pad_m 0.5

  # XY distance (m) below which two detections are grouped together in the
  # proximity-sorted detection list.
  @proximity_cluster_m 0.75

  # Ruler tick lengths in viewBox units. Minor ticks are every 10 cm;
  # major ticks land on full meters and are roughly 3× as long.
  @minor_tick_len 8
  @major_tick_len 24

  # Default per-session visibility of each visual layer. Persons, detections,
  # coverage, placements, world border, height-as-size, trails, labels and
  # ruler start on; velocity arrows start off to keep the overlay uncluttered.
  @default_visuals %{
    world_border: true,
    platform: true,
    ring_panels: true,
    coverage: true,
    placements: true,
    persons: true,
    detections: true,
    trails: true,
    arrows: false,
    height_size: true,
    labels: true,
    ruler: true
  }

  # Legend rows: {feature_key, label}. Rendered in this order.
  @legend_items [
    {:world_border, "World border"},
    {:platform, "Platform"},
    {:ring_panels, "Display ring"},
    {:coverage, "Sensor coverage"},
    {:placements, "Sensor placements"},
    {:persons, "Virtual persons"},
    {:detections, "Detections"},
    {:trails, "Trails"},
    {:arrows, "Velocity arrows"},
    {:height_size, "Height as size"},
    {:labels, "Track labels"},
    {:ruler, "Ruler / grid"}
  ]

  ## LiveView callbacks

  @impl true
  def mount(_params, _session, socket) do
    source_mode = Radar.source_mode()
    layout_devices = Radar.planned_devices()
    devices = Radar.devices() |> Enum.filter(& &1.enabled)
    world_radius = world_radius_for_view()
    platform_radius = Octopus.Installation.platform_radius_m()
    ring_layout = ring_layout_info()

    if connected?(socket) and Radar.configured?() do
      Radar.subscribe()
      Enum.each(devices, &Radar.subscribe_status(&1.device_id))
      if mock_source?(source_mode), do: subscribe_world()
      # Track the Sim3D platform radius so the drawn chill zone matches the mock.
      Phoenix.PubSub.subscribe(Octopus.PubSub, Octopus.Params.Sim3d.topic())
      Process.send_after(self(), :refresh_sensor_statuses, 2_000)
    end

    selected_id =
      cond do
        mock_source?(source_mode) -> :all
        length(devices) == 1 -> hd(devices).device_id
        true -> :all
      end

    selected = Enum.find(devices, &(&1.device_id == selected_id))

    {:ok,
     socket
     |> assign(:radar_configured, Radar.configured?())
     |> assign(:live_available, Radar.live_available?())
     |> assign(:layout_devices, layout_devices)
     |> assign(:devices, devices)
     |> assign(:radial_layout, Radar.radial_layout?())
     |> assign(:layout_start_angle_deg, round(Radar.layout_start_angle_deg()))
     |> assign(:angle_offset_deg, round(Radar.angle_offset_deg()))
     |> assign(:north_panel, Octopus.Installation.north_panel())
     |> assign(:sensor_statuses, build_sensor_statuses(devices))
     |> assign(:selected_device_id, selected_id)
     |> assign(:sensitivity, (selected && selected.sensitivity) || 4)
     |> assign(:source_mode, source_mode)
     |> assign(:max_people, safe_max_people())
     |> assign(:max_people_limit, Radar.max_people_limit())
     |> assign(:max_people_applying, false)
     |> assign(:max_people_applying_until, 0)
     |> assign(:entropy, safe_entropy())
     |> assign(:world_radius, world_radius)
     |> assign(:platform_radius, platform_radius)
     |> assign(:ring_layout, ring_layout)
     |> assign(:world_objects, [])
     |> assign(:visuals, @default_visuals)
     |> assign(:detection_list_mode, :by_sensor)
     |> assign(:bounds_mode, :static)
     |> assign(:static_bounds, bounds_for(selected_id, devices, world_radius))
     |> reset_radar_state()}
  end

  # The canvas always frames the entire simulated world (in every mode) so the
  # world border, the sensors and their coverage, and the detections all share
  # one fixed, fully-visible frame. The extent is padded slightly past the
  # world radius so the border circle isn't clipped at the canvas edge.
  defp bounds_for(_selected_id, _devices, radius), do: world_bounds(radius)

  defp world_bounds(radius) do
    ext = radius * 1.08
    %{min_x: -ext, max_x: ext, min_y: -ext, max_y: ext, range_m: radius}
  end

  defp world_radius_for_view do
    if Installation.arrangement() == :circular do
      Installation.ring_radius_m()
    else
      Radar.world_radius_m()
    end
  end

  defp ring_layout_info do
    case {Installation.arrangement(), Installation.panel_type(), Installation.panel_outer_dimensions_cm()} do
      {:circular, type, {w, _h, d}} when not is_nil(type) ->
        %{
          enabled: true,
          count: Installation.num_panels(),
          width_m: w / 100.0,
          depth_m: d / 100.0
        }

      _ ->
        %{enabled: false, count: 1, width_m: 0.0, depth_m: 0.0}
    end
  end

  # Sensor → letter mapping for labels. Device 1 = "A", 2 = "B", etc.
  defp device_letter(device_id) when is_integer(device_id) do
    <<?A + rem(device_id - 1, 26)>>
  end

  @impl true
  def handle_event("select_sensor", %{"device_id" => "all"}, socket) do
    {:noreply,
     socket
     |> assign(:selected_device_id, :all)
     |> assign(:static_bounds, active_bounds(socket, :all))
     |> reset_radar_state()}
  end

  def handle_event("select_sensor", %{"device_id" => id_str}, socket) do
    case Integer.parse(id_str) do
      {id, ""} ->
        device = Enum.find(socket.assigns.devices, &(&1.device_id == id))

        {:noreply,
         socket
         |> assign(:selected_device_id, id)
         |> assign(:sensitivity, (device && device.sensitivity) || 4)
         |> assign(:static_bounds, active_bounds(socket, id))
         |> reset_radar_state()}

      _ ->
        {:noreply, socket}
    end
  end

  # Toggle between static (canvas matches the sensor's configured X/Y
  # rectangle) and auto (grow-only bounds derived from observed samples).
  def handle_event("toggle_bounds_mode", params, socket) do
    new_mode = if params["auto"] == "true", do: :auto, else: :static

    socket =
      socket
      |> assign(:bounds_mode, new_mode)
      |> apply_bounds_for_mode()
      |> rebuild_view()

    {:noreply, socket}
  end

  def handle_event("set_sensitivity", %{"sensitivity_ui" => ui_str}, socket) do
    with {ui, ""} <- Integer.parse(ui_str),
         true <- ui in 1..9 do
      sensitivity = 10 - ui

      case socket.assigns.selected_device_id do
        :all -> Enum.each(socket.assigns.devices, &Radar.set_sensitivity(&1.device_id, sensitivity))
        id when is_integer(id) -> Radar.set_sensitivity(id, sensitivity)
        _ -> :ok
      end

      {:noreply,
       socket
       |> assign(:sensitivity, sensitivity)
       |> reset_radar_state()}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("set_source_mode", %{"mode" => mode_str}, socket) do
    Radar.set_source_mode(parse_source_mode(mode_str))
    {:noreply, socket}
  end

  # Legacy event name from older UI builds.
  def handle_event("set_mock_mode", %{"mode" => mode_str}, socket) do
    handle_event("set_source_mode", %{"mode" => mode_str}, socket)
  end

  def handle_event("set_max_people", %{"max_people" => v}, socket) do
    case Integer.parse(v) do
      {n, _} ->
        target = n |> max(1) |> min(socket.assigns.max_people_limit)
        Radar.set_max_people(target)

        # The world ramps toward the cap over a few ticks; show a loading state
        # until the live population reaches the target AND a minimum time has
        # elapsed, so the feedback is visible even for near-instant changes.
        applying? = length(socket.assigns.world_objects) != target
        until = System.monotonic_time(:millisecond) + @apply_min_ms

        {:noreply,
         socket
         |> assign(:max_people, target)
         |> assign(:max_people_applying, applying?)
         |> assign(:max_people_applying_until, until)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("set_entropy", %{"entropy" => v}, socket) do
    case Integer.parse(v) do
      {n, _} ->
        Radar.set_entropy(n)
        {:noreply, assign(socket, :entropy, n |> max(0) |> min(100))}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("set_layout_start_angle", %{"layout_start_angle_deg" => v}, socket) do
    case parse_degree(v) do
      {:ok, deg} -> Radar.set_layout_start_angle_deg(deg)
      :error -> :ok
    end

    {:noreply, socket}
  end

  def handle_event("set_angle_offset", %{"angle_offset_deg" => v}, socket) do
    case parse_degree(v) do
      {:ok, deg} -> Radar.set_angle_offset_deg(deg)
      :error -> :ok
    end

    {:noreply, socket}
  end

  def handle_event("set_north_panel", %{"north_panel" => v}, socket) do
    case Integer.parse(v) do
      {n, _} ->
        north_panel = n |> max(1) |> min(socket.assigns.ring_layout.count)
        {:noreply, socket |> assign(:north_panel, north_panel) |> rebuild_view()}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("set_detection_list_mode", %{"mode" => mode}, socket) do
    mode_atom =
      case mode do
        "proximity" -> :by_proximity
        _ -> :by_sensor
      end

    {:noreply, socket |> assign(:detection_list_mode, mode_atom) |> rebuild_view()}
  end

  def handle_event("toggle_visual", %{"feature" => feature}, socket) do
    key = String.to_existing_atom(feature)

    if Map.has_key?(socket.assigns.visuals, key) do
      visuals = Map.update!(socket.assigns.visuals, key, &(!&1))
      {:noreply, socket |> assign(:visuals, visuals) |> rebuild_view()}
    else
      {:noreply, socket}
    end
  end

  def handle_event("toggle_sensor", %{"device_id" => id_str}, socket) do
    case Integer.parse(id_str) do
      {id, ""} ->
        status = Map.get(socket.assigns.sensor_statuses, id, :unavailable)

        # :inactive means the operator stopped it → reactivate; any other
        # state means it's currently running → deactivate.
        if status == :inactive do
          Radar.enable_sensor(id)
        else
          Radar.disable_sensor(id)
        end

        statuses = build_sensor_statuses(socket.assigns.devices)

        selected =
          if status != :inactive and socket.assigns.selected_device_id == id do
            :all
          else
            socket.assigns.selected_device_id
          end

        {:noreply,
         socket
         |> assign(:sensor_statuses, statuses)
         |> assign(:selected_device_id, selected)
         |> assign(:static_bounds, active_bounds(socket, selected))
         |> reset_radar_state()}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("reinitialize", _params, socket) do
    case socket.assigns.selected_device_id do
      nil ->
        {:noreply, socket}

      :all ->
        Enum.each(socket.assigns.devices, &Radar.reinitialize(&1.device_id))
        {:noreply, reset_radar_state(socket)}

      id ->
        _ = Radar.reinitialize(id)
        {:noreply, reset_radar_state(socket)}
    end
  end

  def handle_event("fit_bounds", _params, socket) do
    {min_x, max_x, min_y, max_y, min_z, max_z} = compute_minmax(socket.assigns.samples)

    {:noreply,
     socket
     |> assign(:min_x, min_x)
     |> assign(:max_x, max_x)
     |> assign(:min_y, min_y)
     |> assign(:max_y, max_y)
     |> assign(:min_z, min_z)
     |> assign(:max_z, max_z)
     |> rebuild_view()}
  end

  def handle_info(:refresh_sensor_statuses, socket) do
    Process.send_after(self(), :refresh_sensor_statuses, 2_000)

    {:noreply,
     assign(socket, :sensor_statuses, build_sensor_statuses(socket.assigns.devices))}
  end

  def handle_info({:radar_sensor_status, device_id, new_status}, socket) do
    statuses = Map.put(socket.assigns.sensor_statuses, device_id, new_status)
    {:noreply, assign(socket, :sensor_statuses, statuses)}
  end

  def handle_info({:source_mode_changed, mode}, socket) do
    handle_source_mode_changed(socket, mode)
  end

  def handle_info({:mock_mode_changed, mode}, socket) do
    mode =
      case mode do
        :off -> :live
        other -> other
      end

    handle_source_mode_changed(socket, mode)
  end

  def handle_info({:pose_tweak_changed, %{layout_start_angle_deg: start, angle_offset_deg: offset}}, socket) do
    devices = Radar.devices() |> Enum.filter(& &1.enabled)

    {:noreply,
     socket
     |> assign(:layout_devices, Radar.planned_devices())
     |> assign(:devices, devices)
     |> assign(:layout_start_angle_deg, round(start))
     |> assign(:angle_offset_deg, round(offset))
     |> reset_radar_state()}
  end

  def handle_info({:mock_world, objects}, socket) do
    # Clear the "applying" loading state once the live population has reached the
    # requested cap (it lands exactly on the target while ramping up or down) and
    # the minimum display time has elapsed. The world broadcasts every tick, so
    # this is re-evaluated ~10x/s and clears promptly once both hold.
    reached? = length(objects) == socket.assigns.max_people
    past_floor? = System.monotonic_time(:millisecond) >= socket.assigns.max_people_applying_until
    applying? = socket.assigns.max_people_applying and not (reached? and past_floor?)

    {:noreply,
     socket
     |> assign(:world_objects, objects)
     |> assign(:max_people_applying, applying?)
     |> rebuild_view()}
  end

  @impl true
  def handle_info({:radar_frame, device_id, %Frame{} = frame}, socket) do
    {:noreply, ingest_frame(socket, device_id, frame)}
  end

  def handle_info({:platform_radius_m, value}, socket) do
    {:noreply, socket |> assign(:platform_radius, value) |> rebuild_view()}
  end

  # The Sim3D topic carries other parameter broadcasts too; ignore them.
  def handle_info(_msg, socket), do: {:noreply, socket}

  defp handle_source_mode_changed(socket, mode) do
    if connected?(socket) do
      if mock_source?(mode), do: subscribe_world(), else: unsubscribe_world()
    end

    devices = Radar.devices() |> Enum.filter(& &1.enabled)

    {:noreply,
     socket
     |> assign(:source_mode, mode)
     |> assign(:layout_devices, Radar.planned_devices())
     |> assign(:devices, devices)
     |> assign(:max_people, safe_max_people())
     |> assign(:max_people_applying, false)
     |> assign(:entropy, safe_entropy())
     |> assign(:selected_device_id, :all)
     |> assign(:bounds_mode, :static)
     |> assign(:world_objects, [])
     |> assign(:sensor_statuses, build_sensor_statuses(devices))
     |> assign(:static_bounds, bounds_for(:all, devices, socket.assigns.world_radius))
     |> reset_radar_state()}
  end

  ## State updates

  defp reset_radar_state(socket) do
    socket
    |> assign(:samples, [])
    |> assign(:tracks_now, %{})
    |> assign(:last_frame_number, nil)
    |> assign(:min_z, nil)
    |> assign(:max_z, nil)
    |> assign(:view_targets, [])
    |> assign(:detection_list, [])
    |> assign(:ruler, empty_ruler())
    |> assign(:range_indicators, [])
    |> assign(:ground_truth, [])
    |> assign(:world_sensors, [])
    |> assign(:world_border, nil)
    |> assign(:platform_ring, nil)
    |> apply_bounds_for_mode()
    |> rebuild_view()
  end

  defp apply_bounds_for_mode(socket) do
    case socket.assigns.bounds_mode do
      :static ->
        sb = socket.assigns.static_bounds

        socket
        |> assign(:min_x, sb.min_x)
        |> assign(:max_x, sb.max_x)
        |> assign(:min_y, sb.min_y)
        |> assign(:max_y, sb.max_y)

      :auto ->
        {min_x, max_x, min_y, max_y, _min_z, _max_z} =
          compute_minmax(socket.assigns.samples)

        socket
        |> assign(:min_x, min_x)
        |> assign(:max_x, max_x)
        |> assign(:min_y, min_y)
        |> assign(:max_y, max_y)
    end
  end

  # Bounds to use for a (re)selection, honoring mock mode (world disk) vs
  # real hardware (configured rectangle).
  defp active_bounds(socket, _selected_id) do
    bounds_for(socket.assigns.selected_device_id, socket.assigns.devices, socket.assigns.world_radius)
  end

  defp empty_ruler,
    do: %{x_axis_visible: false, y_axis_visible: false, origin_x: 0, origin_y: 0, ticks: []}

  defp ingest_frame(socket, device_id, %Frame{tracks: tracks, frame_number: frame_number}) do
    now = System.monotonic_time(:millisecond)
    cutoff = now - @window_ms
    fade_cutoff = now - @fade_ms
    selected = socket.assigns.selected_device_id
    include_samples? = selected == :all or selected == device_id

    tracks_now =
      tracks
      |> Enum.reduce(socket.assigns.tracks_now, fn %Track{} = t, acc ->
        Map.put(acc, {device_id, t.id}, %{
          device_id: device_id,
          id: t.id,
          x: t.x,
          y: t.y,
          z: t.z,
          vx: t.vx,
          vy: t.vy,
          vz: t.vz,
          last_seen: now
        })
      end)
      |> Enum.reject(fn {_key, t} -> t.last_seen < fade_cutoff end)
      |> Map.new()

    new_samples =
      if include_samples? do
        Enum.map(tracks, fn %Track{id: id, x: x, y: y, z: z} ->
          %{ts: now, device_id: device_id, id: id, x: x, y: y, z: z}
        end)
      else
        []
      end

    samples =
      if include_samples? do
        (new_samples ++ socket.assigns.samples)
        |> Enum.filter(&(&1.ts >= cutoff))
      else
        socket.assigns.samples
      end

    a = socket.assigns

    {min_x, max_x, min_y, max_y} =
      if include_samples?, do: update_xy_bounds(a, new_samples), else: {a.min_x, a.max_x, a.min_y, a.max_y}

    {min_z, max_z} =
      if include_samples?, do: grow_bounds(new_samples, a.min_z, a.max_z, :z), else: {a.min_z, a.max_z}

    socket
    |> assign(:samples, samples)
    |> assign(:tracks_now, tracks_now)
    |> assign(:last_frame_number, if(include_samples?, do: frame_number, else: a.last_frame_number))
    |> assign(:min_x, min_x)
    |> assign(:max_x, max_x)
    |> assign(:min_y, min_y)
    |> assign(:max_y, max_y)
    |> assign(:min_z, min_z)
    |> assign(:max_z, max_z)
    |> rebuild_view()
  end

  defp update_xy_bounds(%{bounds_mode: :static} = a, _new_samples) do
    {a.min_x, a.max_x, a.min_y, a.max_y}
  end

  defp update_xy_bounds(%{bounds_mode: :auto} = a, new_samples) do
    {min_x, max_x} = grow_bounds(new_samples, a.min_x, a.max_x, :x)
    {min_y, max_y} = grow_bounds(new_samples, a.min_y, a.max_y, :y)
    {min_x, max_x, min_y, max_y}
  end

  defp grow_bounds(new_samples, min_v, max_v, key) do
    values = Enum.map(new_samples, &Map.fetch!(&1, key))

    case {min_v, max_v, values} do
      {nil, nil, []} ->
        {nil, nil}

      {nil, nil, vs} ->
        {raw_min, raw_max} = Enum.min_max(vs)
        pad_range(raw_min, raw_max)

      {_min_v, _max_v, []} ->
        {min_v, max_v}

      {_min_v, _max_v, vs} ->
        {sample_min, sample_max} = Enum.min_max(vs)
        pad_range(min(min_v, sample_min), max(max_v, sample_max))
    end
  end

  # Recompute everything that depends on the current bounds + tracks +
  # samples + world snapshot.
  defp rebuild_view(socket) do
    a = socket.assigns

    {min_x, max_x} = pad_range(a.min_x, a.max_x)
    {min_y, max_y} = pad_range(a.min_y, a.max_y)

    view_targets =
      build_view_targets(%{
        tracks_now: a.tracks_now,
        samples: a.samples,
        min_x: min_x,
        max_x: max_x,
        min_y: min_y,
        max_y: max_y,
        selected: a.selected_device_id
      })

    ruler = build_ruler(min_x, max_x, min_y, max_y)

    active_devices = Enum.filter(a.devices, &Radar.sensor_active?(&1.device_id))
    active_ids = MapSet.new(active_devices, & &1.device_id)

    range_indicators =
      build_range_indicators(
        a.layout_devices,
        active_ids,
        a.selected_device_id,
        a.tracks_now,
        min_x,
        max_x,
        min_y,
        max_y
      )

    world_sensors =
      build_world_sensors(a.layout_devices, active_devices, a.tracks_now, min_x, max_x, min_y, max_y)

    # The world border frames every mode; ground-truth people only exist in
    # mock mode.
    world_border = build_world_border(a.world_radius, min_x, max_x, min_y, max_y)
    platform_ring = build_platform_ring(a.platform_radius, min_x, max_x, min_y, max_y)
    ring_panels =
      if a.ring_layout.enabled do
        build_ring_panels(
          a.world_radius,
          a.ring_layout,
          a.north_panel,
          min_x,
          max_x,
          min_y,
          max_y
        )
      else
        []
      end

    ground_truth =
      if mock_source?(a.source_mode),
        do: [],
        else: build_ground_truth(a.world_objects, min_x, max_x, min_y, max_y)

    detection_list =
      build_detection_list(
        a.tracks_now,
        a.devices,
        a.selected_device_id,
        a.detection_list_mode
      )

    socket
    |> assign(:view_targets, view_targets)
    |> assign(:detection_list, detection_list)
    |> assign(:ruler, ruler)
    |> assign(:range_indicators, range_indicators)
    |> assign(:world_sensors, world_sensors)
    |> assign(:ground_truth, ground_truth)
    |> assign(:world_border, world_border)
    |> assign(:platform_ring, platform_ring)
    |> assign(:ring_panels, ring_panels)
  end

  # One coverage ellipse per planned sensor in the current selection, centered on
  # the sensor's global mount position. Inactive sensors use neutral gray; active
  # sensors use their per-sensor hue.
  defp build_range_indicators(_layout_devices, _active_ids, nil, _tracks_now, _, _, _, _), do: []

  defp build_range_indicators(layout_devices, active_ids, :all, tracks_now, min_x, max_x, min_y, max_y) do
    detecting = devices_with_detections(tracks_now)

    Enum.map(layout_devices, fn device ->
      active? = MapSet.member?(active_ids, device.device_id)
      detecting? = active? and MapSet.member?(detecting, device.device_id)
      range_indicator(device, active?, detecting?, min_x, max_x, min_y, max_y)
    end)
  end

  defp build_range_indicators(layout_devices, active_ids, device_id, tracks_now, min_x, max_x, min_y, max_y)
       when is_integer(device_id) do
    detecting = devices_with_detections(tracks_now)

    case Enum.find(layout_devices, &(&1.device_id == device_id)) do
      nil ->
        []

      device ->
        active? = MapSet.member?(active_ids, device.device_id)
        detecting? = active? and MapSet.member?(detecting, device.device_id)
        [range_indicator(device, active?, detecting?, min_x, max_x, min_y, max_y)]
    end
  end

  defp range_indicator(device, active?, detecting?, min_x, max_x, min_y, max_y) do
    range_m = device.range_cm / 100.0
    {tx, ty} = sensor_position(device)

    %{
      id: device.device_id,
      cx: world_to_svg_x(tx, min_x, max_x),
      cy: world_to_svg_y(ty, min_y, max_y),
      rx: range_m / (max_x - min_x) * @vb,
      ry: range_m / (max_y - min_y) * @vb,
      color: placement_marker_color(device.device_id, active?, detecting?),
      active?: active?
    }
  end

  # Sensor placement markers (square + label) in the global frame.
  defp build_world_sensors(layout_devices, active_devices, tracks_now, min_x, max_x, min_y, max_y) do
    active_ids = MapSet.new(active_devices, & &1.device_id)
    detecting = devices_with_detections(tracks_now)

    Enum.map(layout_devices, fn device ->
      active? = MapSet.member?(active_ids, device.device_id)
      detecting? = active? and MapSet.member?(detecting, device.device_id)

      {tx, ty} = sensor_position(device)
      axis_len_m = @sensor_marker_half * (max_x - min_x) / @vb * 0.75

      # Local axes in the global frame (matches Transform): +X along the outward
      # radial (angle_deg + rotation_deg), +Y 90° CCW from it (right-handed).
      phi = (device.angle_deg + device.rotation_deg) * :math.pi() / 180.0
      {x_dx, x_dy} = {:math.cos(phi), :math.sin(phi)}
      {y_dx, y_dy} = {-:math.sin(phi), :math.cos(phi)}

      %{
        cx: world_to_svg_x(tx, min_x, max_x),
        cy: world_to_svg_y(ty, min_y, max_y),
        x_axis_x: world_to_svg_x(tx + x_dx * axis_len_m, min_x, max_x),
        x_axis_y: world_to_svg_y(ty + x_dy * axis_len_m, min_y, max_y),
        y_axis_x: world_to_svg_x(tx + y_dx * axis_len_m, min_x, max_x),
        y_axis_y: world_to_svg_y(ty + y_dy * axis_len_m, min_y, max_y),
        half: @sensor_marker_half,
        label: device_letter(device.device_id),
        color: placement_marker_color(device.device_id, active?, detecting?),
        fill_opacity: placement_fill_opacity(active?, detecting?),
        stroke: if(active?, do: "#404040", else: "#9ca3af"),
        # SVG rotate() is clockwise with Y pointing down, so a world angle φ
        # (CCW) draws the square at −φ.
        rotation: -(device.angle_deg + device.rotation_deg)
      }
    end)
  end

  defp placement_marker_color(_device_id, false, _detecting?), do: "#d1d5db"

  defp placement_marker_color(device_id, true, detecting?) do
    sensor_placement_color(device_id, detecting?)
  end

  defp placement_fill_opacity(true, true), do: 0.58
  defp placement_fill_opacity(true, false), do: 0.35
  defp placement_fill_opacity(false, _), do: 0.22

  defp devices_with_detections(tracks_now) do
    tracks_now
    |> Map.values()
    |> Enum.map(& &1.device_id)
    |> MapSet.new()
  end

  # LED displays on the installation ring (+Y = north). Panel fronts face inward;
  # the front-face center sits on the world border at `radius_m`, with the panel
  # body extending outward (center at R + depth/2).
  defp build_ring_panels(radius_m, ring_layout, north_panel, min_x, max_x, min_y, max_y) do
    panel_count = ring_layout.count
    width_m = ring_layout.width_m
    depth_m = ring_layout.depth_m
    center_r = radius_m + depth_m / 2.0
    step_deg = 360.0 / panel_count

    Enum.map(1..panel_count, fn n ->
      offset = Integer.mod(n - north_panel, panel_count)
      theta_deg = offset * step_deg
      theta_rad = theta_deg * :math.pi() / 180.0

      tx = center_r * :math.sin(theta_rad)
      ty = center_r * :math.cos(theta_rad)

      label_r = radius_m + depth_m + 0.25
      label_tx = label_r * :math.sin(theta_rad)
      label_ty = label_r * :math.cos(theta_rad)

      %{
        number: n,
        cx: world_to_svg_x(tx, min_x, max_x),
        cy: world_to_svg_y(ty, min_y, max_y),
        label_cx: world_to_svg_x(label_tx, min_x, max_x),
        label_cy: world_to_svg_y(label_ty, min_y, max_y),
        half_w: width_m / (max_x - min_x) * @vb / 2,
        half_h: depth_m / (max_y - min_y) * @vb / 2,
        rotation: theta_deg
      }
    end)
  end

  # Ground-truth people as small black dots.
  defp build_ground_truth(objects, min_x, max_x, min_y, max_y) do
    Enum.map(objects, fn o ->
      %{
        id: o.id,
        cx: world_to_svg_x(o.x, min_x, max_x),
        cy: world_to_svg_y(o.y, min_y, max_y),
        r: @ground_truth_r
      }
    end)
  end

  # The outer edge of the simulated world (a circle of radius `radius_m`
  # centered on the origin), as an ellipse to honor non-uniform axis scales.
  defp build_world_border(radius_m, min_x, max_x, min_y, max_y) do
    %{
      cx: world_to_svg_x(0.0, min_x, max_x),
      cy: world_to_svg_y(0.0, min_y, max_y),
      rx: radius_m / (max_x - min_x) * @vb,
      ry: radius_m / (max_y - min_y) * @vb
    }
  end

  # The central platform ("chill zone", radius `platform_radius_m`), drawn the
  # same way as the world border so it honors non-uniform axis scales.
  defp build_platform_ring(nil, _min_x, _max_x, _min_y, _max_y), do: nil

  defp build_platform_ring(radius_m, min_x, max_x, min_y, max_y) do
    %{
      cx: world_to_svg_x(0.0, min_x, max_x),
      cy: world_to_svg_y(0.0, min_y, max_y),
      rx: radius_m / (max_x - min_x) * @vb,
      ry: radius_m / (max_y - min_y) * @vb
    }
  end

  defp sensor_position(device) do
    angle_rad = device.angle_deg * :math.pi() / 180.0
    distance_m = device.distance_cm / 100.0
    {distance_m * :math.cos(angle_rad), distance_m * :math.sin(angle_rad)}
  end

  defp compute_minmax([]) do
    {-@minmax_pad_m, @minmax_pad_m, -@minmax_pad_m, @minmax_pad_m, -@minmax_pad_m, @minmax_pad_m}
  end

  defp compute_minmax(samples) do
    {min_x, max_x} = samples |> Enum.map(& &1.x) |> Enum.min_max()
    {min_y, max_y} = samples |> Enum.map(& &1.y) |> Enum.min_max()
    {min_z, max_z} = samples |> Enum.map(& &1.z) |> Enum.min_max()
    {min_x, max_x} = pad_range(min_x, max_x)
    {min_y, max_y} = pad_range(min_y, max_y)
    {min_z, max_z} = pad_range(min_z, max_z)
    {min_x, max_x, min_y, max_y, min_z, max_z}
  end

  defp pad_range(nil, nil), do: {-@minmax_pad_m, @minmax_pad_m}

  defp pad_range(min, max) do
    if max - min < 2 * @minmax_pad_m do
      mid = (min + max) / 2
      {mid - @minmax_pad_m, mid + @minmax_pad_m}
    else
      {min, max}
    end
  end

  ## Render

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(:legend_items, @legend_items)
      |> assign(:detection_fixed_r, @detection_fixed_r)

    ~H"""
    <div class="container mx-auto p-4">
      <div class="card bg-base-100 shadow-md">
        <div class="card-body flex flex-col gap-3 min-h-0">
          <div class="flex items-center justify-between gap-4 shrink-0">
            <h1 class="card-title text-2xl">Radar</h1>
            <%= cond do %>
              <% not @radar_configured -> %>
                <span class="text-sm opacity-70">
                  Radar not defined for this installation
                </span>
              <% @source_mode == :off -> %>
                <span class="text-sm opacity-70">
                  Source off · {length(@layout_devices)} sensor{if length(@layout_devices) == 1,
                    do: "",
                    else: "s"} planned
                </span>
              <% @devices == [] -> %>
                <span class="text-sm opacity-70">No sensors active</span>
              <% true -> %>
                <span class="text-sm opacity-70">
                  {length(@devices)} sensor{if length(@devices) == 1, do: "", else: "s"}
                </span>
            <% end %>
          </div>

          <%= if not @radar_configured do %>
            <div class="alert alert-info mt-4">
              <span>
                Add a <code>:radar</code> block to the active installation module to use radar.
              </span>
            </div>
          <% else %>
              <div class="flex flex-row flex-nowrap gap-4 min-h-0 items-stretch">
                <div class="w-64 shrink-0 overflow-y-auto flex flex-col gap-3 max-h-[calc(100vh-9rem)]">
                  <div class="flex flex-col gap-2">
                    <p class="text-xs font-semibold opacity-70">Detections</p>
                    <div class="join w-full" id="radar-detection-list-mode">
                      <button
                        type="button"
                        phx-click="set_detection_list_mode"
                        phx-value-mode="sensor"
                        class={[
                          "btn btn-sm join-item flex-1",
                          if(@detection_list_mode == :by_sensor, do: "btn-primary", else: "btn-outline")
                        ]}
                      >
                        By sensor
                      </button>
                      <button
                        type="button"
                        phx-click="set_detection_list_mode"
                        phx-value-mode="proximity"
                        class={[
                          "btn btn-sm join-item flex-1",
                          if(@detection_list_mode == :by_proximity, do: "btn-primary", else: "btn-outline")
                        ]}
                      >
                        By proximity
                      </button>
                    </div>
                  </div>

                  <%= if @detection_list == [] do %>
                    <p class="text-sm opacity-50 italic">No detections</p>
                  <% else %>
                    <div class="flex flex-col gap-3">
                      <%= for group <- @detection_list do %>
                        <div class="flex flex-col gap-1">
                          <%= if group.type == :sensor_group do %>
                            <p class="text-xs font-semibold flex items-center gap-1.5">
                              <span
                                class="inline-block w-2.5 h-2.5 rounded-full shrink-0"
                                style={"background-color: #{group.color}"}
                              />
                              Sensor {group.letter}
                              <span class="font-normal opacity-60">({length(group.items)})</span>
                            </p>
                          <% else %>
                            <p class="text-xs font-semibold opacity-80">
                              Group {group.id}
                              <span class="font-normal opacity-60">
                                · {length(group.items)} · {fmt_m(group.span_m)} spread
                              </span>
                            </p>
                          <% end %>
                          <ul class="flex flex-col gap-1">
                            <%= for item <- group.items do %>
                              <li
                                class="text-xs font-mono rounded px-2 py-1.5 bg-base-200/80 border border-base-300/60"
                                style={"opacity: #{fmt_f(item.opacity)}"}
                              >
                                <div class="flex items-center justify-between gap-2">
                                  <span class="flex items-center gap-1.5 min-w-0">
                                    <span
                                      class="inline-block w-2 h-2 rounded-full shrink-0"
                                      style={"background-color: #{item.color}"}
                                    />
                                    <span class="font-bold">{item.label}</span>
                                  </span>
                                  <%= if item.speed > 0.05 do %>
                                    <span class="opacity-60 shrink-0">{fmt_m(item.speed)}/s</span>
                                  <% end %>
                                </div>
                                <div class="opacity-70 mt-0.5 tabular-nums">
                                  x {fmt_m(item.x)} · y {fmt_m(item.y)} · z {fmt_m(item.z)}
                                </div>
                              </li>
                            <% end %>
                          </ul>
                        </div>
                      <% end %>
                    </div>
                  <% end %>
                </div>

                <div class="flex-1 min-w-0 min-h-0 flex items-center justify-center">
                  <div
                    class="aspect-square bg-base-200 rounded w-full max-h-[calc(100vh-9rem)]"
                    style="height: min(calc(100vh - 9rem), 100%);"
                  >
                    <svg viewBox="0 0 1000 1000" class="w-full h-full">
                      <%!-- World border --%>
                      <%= if @visuals.world_border and @world_border do %>
                        <ellipse
                          cx={fmt_f(@world_border.cx)}
                          cy={fmt_f(@world_border.cy)}
                          rx={fmt_f(@world_border.rx)}
                          ry={fmt_f(@world_border.ry)}
                          fill="none"
                          stroke="#9ca3af"
                          stroke-width="2"
                          stroke-dasharray="6,6"
                        />
                      <% end %>

                      <%!-- Central platform (chill zone) --%>
                      <%= if @visuals.platform and @platform_ring do %>
                        <ellipse
                          cx={fmt_f(@platform_ring.cx)}
                          cy={fmt_f(@platform_ring.cy)}
                          rx={fmt_f(@platform_ring.rx)}
                          ry={fmt_f(@platform_ring.ry)}
                          fill="#8B4513"
                          fill-opacity="0.08"
                          stroke="#a16207"
                          stroke-width="2"
                          stroke-dasharray="3,5"
                        />
                      <% end %>

                      <%!-- LED display ring on the installation border --%>
                      <%= if @visuals.ring_panels and @ring_layout.enabled do %>
                        <%= for p <- @ring_panels do %>
                          <g transform={"rotate(#{fmt_f(p.rotation)}, #{fmt_f(p.cx)}, #{fmt_f(p.cy)})"}>
                            <rect
                              x={fmt_f(p.cx - p.half_w)}
                              y={fmt_f(p.cy - p.half_h)}
                              width={fmt_f(p.half_w * 2)}
                              height={fmt_f(p.half_h * 2)}
                              rx="2"
                              fill="#e5e7eb"
                              fill-opacity="0.85"
                              stroke="#404040"
                              stroke-width="1.5"
                            />
                          </g>
                          <text
                            x={fmt_f(p.label_cx)}
                            y={fmt_f(p.label_cy)}
                            text-anchor="middle"
                            dominant-baseline="central"
                            font-size="28"
                            font-weight="bold"
                            fill="#1f2937"
                          >
                            {p.number}
                          </text>
                        <% end %>
                      <% end %>

                      <%!-- Sensor coverage: radial fill fading with distance (signal
                           strength) plus a 50% gray border marking the range edge. --%>
                      <%= if @visuals.coverage do %>
                        <defs>
                          <%= for r <- @range_indicators do %>
                            <radialGradient id={"rangegrad-#{r.id}"}>
                              <%= if r.active? do %>
                                <stop offset="0%" stop-color={r.color} stop-opacity="0.5" />
                                <stop offset="65%" stop-color={r.color} stop-opacity="0.18" />
                                <stop offset="100%" stop-color={r.color} stop-opacity="0" />
                              <% else %>
                                <stop offset="0%" stop-color={r.color} stop-opacity="0.12" />
                                <stop offset="100%" stop-color={r.color} stop-opacity="0" />
                              <% end %>
                            </radialGradient>
                          <% end %>
                        </defs>
                        <%= for r <- @range_indicators do %>
                          <ellipse
                            cx={fmt_f(r.cx)}
                            cy={fmt_f(r.cy)}
                            rx={fmt_f(r.rx)}
                            ry={fmt_f(r.ry)}
                            fill={"url(#rangegrad-#{r.id})"}
                            stroke={if(r.active?, do: "#808080", else: "#9ca3af")}
                            stroke-opacity={if(r.active?, do: "0.5", else: "0.7")}
                            stroke-width="2"
                          />
                        <% end %>
                      <% end %>

                      <%!-- Ruler / grid axes --%>
                      <%= if @visuals.ruler do %>
                        <g stroke="black">
                          <%= if @ruler.x_axis_visible do %>
                            <line
                              x1="0"
                              y1={fmt_f(@ruler.origin_y)}
                              x2="1000"
                              y2={fmt_f(@ruler.origin_y)}
                              stroke-width="1"
                              stroke-opacity="0.3"
                            />
                          <% end %>
                          <%= if @ruler.y_axis_visible do %>
                            <line
                              x1={fmt_f(@ruler.origin_x)}
                              y1="0"
                              x2={fmt_f(@ruler.origin_x)}
                              y2="1000"
                              stroke-width="1"
                              stroke-opacity="0.3"
                            />
                          <% end %>
                          <%= for tick <- @ruler.ticks do %>
                            <line
                              x1={fmt_f(tick.x1)}
                              y1={fmt_f(tick.y1)}
                              x2={fmt_f(tick.x2)}
                              y2={fmt_f(tick.y2)}
                              stroke-width={if tick.major?, do: "2", else: "1"}
                              stroke-opacity={if tick.major?, do: "0.7", else: "0.35"}
                            />
                          <% end %>
                        </g>
                      <% end %>

                      <%!-- Sensor placements --%>
                      <%= if @visuals.placements do %>
                        <%= for s <- @world_sensors do %>
                          <g>
                            <line
                              x1={fmt_f(s.cx)}
                              y1={fmt_f(s.cy)}
                              x2={fmt_f(s.x_axis_x)}
                              y2={fmt_f(s.x_axis_y)}
                              stroke="#dc2626"
                              stroke-width="3"
                              stroke-linecap="round"
                            />
                            <line
                              x1={fmt_f(s.cx)}
                              y1={fmt_f(s.cy)}
                              x2={fmt_f(s.y_axis_x)}
                              y2={fmt_f(s.y_axis_y)}
                              stroke="#2563eb"
                              stroke-width="3"
                              stroke-linecap="round"
                            />
                            <g transform={"rotate(#{fmt_f(s.rotation)}, #{fmt_f(s.cx)}, #{fmt_f(s.cy)})"}>
                              <rect
                                x={fmt_f(s.cx - s.half)}
                                y={fmt_f(s.cy - s.half)}
                                width={fmt_f(s.half * 2)}
                                height={fmt_f(s.half * 2)}
                                rx="3"
                                fill={s.color}
                                fill-opacity={fmt_f(s.fill_opacity)}
                                stroke={s.stroke}
                                stroke-width="2"
                              />
                              <text
                                x={fmt_f(s.cx)}
                                y={fmt_f(s.cy)}
                                text-anchor="middle"
                                dominant-baseline="central"
                                font-size="22"
                                font-weight="bold"
                                fill="black"
                              >
                                {s.label}
                              </text>
                            </g>
                          </g>
                        <% end %>
                      <% end %>

                      <%!-- Ground-truth people --%>
                      <%= if @visuals.persons do %>
                        <%= for g <- @ground_truth do %>
                          <circle cx={fmt_f(g.cx)} cy={fmt_f(g.cy)} r={fmt_f(g.r)} fill="black" />
                        <% end %>
                      <% end %>

                      <%!-- Detections --%>
                      <%= if @visuals.detections do %>
                        <%= for v <- @view_targets do %>
                          <g opacity={fmt_f(v.opacity)}>
                            <%= if @visuals.trails do %>
                              <%= for seg <- v.trail do %>
                                <line
                                  x1={fmt_f(seg.x1)}
                                  y1={fmt_f(seg.y1)}
                                  x2={fmt_f(seg.x2)}
                                  y2={fmt_f(seg.y2)}
                                  stroke={seg.color}
                                  stroke-width="3"
                                  stroke-linecap="round"
                                  stroke-opacity="0.5"
                                />
                              <% end %>
                            <% end %>
                            <%= if @visuals.arrows do %>
                              <line
                                x1={fmt_f(v.cx)}
                                y1={fmt_f(v.cy)}
                                x2={fmt_f(v.arrow_x)}
                                y2={fmt_f(v.arrow_y)}
                                stroke={v.color}
                                stroke-width="3"
                                stroke-linecap="round"
                              />
                              <circle cx={fmt_f(v.arrow_x)} cy={fmt_f(v.arrow_y)} r="4" fill={v.color} />
                            <% end %>
                            <circle
                              cx={fmt_f(v.cx)}
                              cy={fmt_f(v.cy)}
                              r={fmt_f(if @visuals.height_size, do: v.radius, else: @detection_fixed_r)}
                              fill={v.color}
                              fill-opacity="0.5"
                              stroke={v.color}
                              stroke-width="1.5"
                            />
                            <%= if @visuals.labels do %>
                              <text
                                x={fmt_f(v.cx)}
                                y={fmt_f(v.cy)}
                                text-anchor="middle"
                                dominant-baseline="central"
                                font-size="18"
                                font-weight="bold"
                                fill="black"
                              >
                                {v.label}
                              </text>
                            <% end %>
                          </g>
                        <% end %>
                      <% end %>
                    </svg>
                  </div>
                </div>

                <div class="w-72 shrink-0 overflow-y-auto flex flex-col gap-4 max-h-[calc(100vh-9rem)]">
                  <div class="flex flex-col gap-3">
                    <p class="text-xs font-semibold opacity-70">Source</p>
                    <div class="flex flex-wrap gap-1 w-full" id="radar-source-mode">
                      <%= for {value, label, disabled?} <- source_mode_options(@live_available) do %>
                        <button
                          type="button"
                          phx-click="set_source_mode"
                          phx-value-mode={value}
                          disabled={disabled?}
                          title={source_mode_button_title(value, disabled?)}
                          class={[
                            "btn btn-sm flex-1 min-w-[45%]",
                            if(Atom.to_string(@source_mode) == value, do: "btn-primary", else: "btn-outline"),
                            disabled? && "btn-disabled"
                          ]}
                        >
                          {label}
                        </button>
                      <% end %>
                    </div>
                  </div>

                  <div class="flex flex-col gap-2">
                    <p class="text-xs font-semibold opacity-70">Sensors</p>
                    <div class="flex flex-wrap gap-1">
                      <%= for d <- @devices do %>
                        <button
                          type="button"
                          phx-click="toggle_sensor"
                          phx-value-device_id={d.device_id}
                          title={sensor_tooltip(d, @sensor_statuses[d.device_id])}
                          class={[
                            "btn btn-sm font-mono min-w-[2.5rem]",
                            sensor_status_class(@sensor_statuses[d.device_id])
                          ]}
                        >
                          {device_letter(d.device_id)}
                        </button>
                      <% end %>
                    </div>
                    <form phx-change="select_sensor">
                      <select
                        id="radar-sensor"
                        name="device_id"
                        class="select select-bordered w-full h-10 text-sm leading-normal"
                      >
                        <%= for d <- @devices do %>
                          <option value={d.device_id} selected={d.device_id == @selected_device_id}>
                            Sensor {device_letter(d.device_id)} — {d.port}
                          </option>
                        <% end %>
                        <option value="all" selected={@selected_device_id == :all}>
                          All sensors
                        </option>
                      </select>
                    </form>
                  </div>

                  <%= if mock_source?(@source_mode) do %>
                    <form phx-change="set_max_people" class="flex flex-col gap-1">
                      <label for="radar-max-people" class="text-xs font-semibold opacity-70">
                        Max people
                      </label>
                      <div class="join w-full">
                        <input
                          id="radar-max-people"
                          name="max_people"
                          type="number"
                          inputmode="numeric"
                          min="1"
                          max={@max_people_limit}
                          value={@max_people}
                          phx-debounce="400"
                          class="input input-bordered input-sm join-item w-full font-mono text-right"
                        />
                        <span class="join-item btn btn-sm btn-disabled font-mono pointer-events-none">
                          / {@max_people_limit}
                        </span>
                      </div>
                      <span
                        :if={@max_people_applying}
                        class="flex items-center gap-1 text-xs opacity-70"
                        title="Population is ramping to the requested cap"
                      >
                        <svg class="animate-spin h-3 w-3" viewBox="0 0 24 24" fill="none">
                          <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" />
                          <path
                            class="opacity-75"
                            fill="currentColor"
                            d="M4 12a8 8 0 018-8v4a4 4 0 00-4 4H4z"
                          />
                        </svg>
                        {length(@world_objects)}/{@max_people}
                      </span>
                    </form>
                    <form phx-change="set_entropy" class="flex flex-col gap-1">
                      <label for="radar-entropy" class="text-xs font-semibold opacity-70">
                        Activity
                      </label>
                      <input
                        id="radar-entropy"
                        name="entropy"
                        type="range"
                        min="0"
                        max="100"
                        step="5"
                        value={@entropy}
                        phx-debounce="200"
                        class="range range-sm w-full"
                      />
                      <span class="text-sm font-mono text-right">{@entropy}%</span>
                    </form>
                  <% end %>

                  <%= if @source_mode == :live do %>
                    <form phx-change="set_sensitivity" class="flex flex-col gap-1">
                      <label for="radar-sensitivity" class="text-xs font-semibold opacity-70">
                        Sensitivity
                      </label>
                      <div class="flex items-center gap-2">
                        <span class="text-xs opacity-60">lower</span>
                        <input
                          id="radar-sensitivity"
                          name="sensitivity_ui"
                          type="range"
                          min="1"
                          max="9"
                          step="1"
                          value={10 - @sensitivity}
                          phx-debounce="500"
                          class="range range-sm grow"
                        />
                        <span class="text-xs opacity-60">higher</span>
                      </div>
                    </form>
                  <% end %>

                  <%= if @radial_layout do %>
                    <form phx-change="set_layout_start_angle" class="flex flex-col gap-1">
                      <label for="radar-layout-start-angle" class="text-xs font-semibold opacity-70">
                        Layout start
                      </label>
                      <input
                        id="radar-layout-start-angle"
                        name="layout_start_angle_deg"
                        type="range"
                        min="0"
                        max="359"
                        step="1"
                        value={@layout_start_angle_deg}
                        class="range range-sm w-full"
                      />
                      <span class="text-sm font-mono text-right">{@layout_start_angle_deg}°</span>
                    </form>
                    <form phx-change="set_angle_offset" class="flex flex-col gap-1">
                      <label for="radar-angle-offset" class="text-xs font-semibold opacity-70">
                        Sensor rotation
                      </label>
                      <input
                        id="radar-angle-offset"
                        name="angle_offset_deg"
                        type="range"
                        min="0"
                        max="359"
                        step="1"
                        value={@angle_offset_deg}
                        class="range range-sm w-full"
                      />
                      <span class="text-sm font-mono text-right">{@angle_offset_deg}°</span>
                    </form>
                  <% end %>

                  <%= if @ring_layout.enabled do %>
                    <form phx-change="set_north_panel" class="flex flex-col gap-1">
                      <label for="radar-north-panel" class="text-xs font-semibold opacity-70">
                        North panel
                      </label>
                      <input
                        id="radar-north-panel"
                        name="north_panel"
                        type="range"
                        min="1"
                        max={@ring_layout.count}
                        step="1"
                        value={@north_panel}
                        class="range range-sm w-full"
                      />
                      <span class="text-sm font-mono text-right">{@north_panel}</span>
                    </form>
                  <% end %>

                  <button
                    id="radar-reinit"
                    type="button"
                    class="btn btn-outline btn-sm w-full"
                    phx-click="reinitialize"
                  >
                    <%= if @selected_device_id == :all do %>
                      Reinitialize all sensors
                    <% else %>
                      Reinitialize sensor
                    <% end %>
                  </button>

                  <div class="flex flex-col gap-2 border-t border-base-300 pt-3">
                    <p class="text-xs font-semibold opacity-70">Visual features</p>
                    <%= for {key, label} <- @legend_items do %>
                      <label class="flex items-center gap-2 cursor-pointer text-sm">
                        <input
                          type="checkbox"
                          class="checkbox checkbox-xs"
                          checked={@visuals[key]}
                          phx-click="toggle_visual"
                          phx-value-feature={key}
                        />
                        <span>{label}</span>
                      </label>
                    <% end %>
                  </div>
                </div>
              </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  ## View-model construction

  defp build_view_targets(%{tracks_now: tracks_now}) when map_size(tracks_now) == 0, do: []

  defp build_view_targets(assigns) do
    %{
      tracks_now: tracks_now,
      samples: samples,
      min_x: min_x,
      max_x: max_x,
      min_y: min_y,
      max_y: max_y,
      selected: selected
    } = assigns

    now = System.monotonic_time(:millisecond)
    trail_cutoff = now - @trail_ms

    samples_by_key = group_samples_by_key(samples, trail_cutoff)

    Enum.map(tracks_now, fn {{device_id, id} = key, t} ->
      cx = world_to_svg_x(t.x, min_x, max_x)
      cy = world_to_svg_y(t.y, min_y, max_y)
      age = now - t.last_seen
      opacity = max(0.0, 1.0 - age / @fade_ms)

      arrow_dx = clamp(t.vx * @velocity_scale, -@velocity_max_len, @velocity_max_len)
      arrow_dy = clamp(t.vy * @velocity_scale, -@velocity_max_len, @velocity_max_len)

      hue = sensor_hue(device_id)

      trail_segments =
        samples_by_key
        |> Map.get(key, [])
        |> build_trail_segments(now, hue, min_x, max_x, min_y, max_y)

      %{
        label: track_label(device_id, id, selected),
        cx: cx,
        cy: cy,
        radius: radius_for_z(t.z),
        opacity: opacity,
        color: sensor_color(device_id),
        arrow_x: cx + arrow_dx,
        arrow_y: cy - arrow_dy,
        trail: trail_segments
      }
    end)
  end

  # In :all mode every label is prefixed by the source sensor's letter so two
  # sensors reporting the same numeric id are distinguishable.
  defp track_label(device_id, id, :all), do: "#{device_letter(device_id)}#{id}"
  defp track_label(_device_id, id, _selected), do: Integer.to_string(id)

  defp build_detection_list(tracks_now, devices, selected, mode) do
    tracks_now
    |> tracks_to_list(selected)
    |> case do
      [] -> []
      tracks -> apply_detection_list_mode(tracks, devices, mode)
    end
  end

  defp tracks_to_list(tracks_now, selected) do
    now = System.monotonic_time(:millisecond)

    Enum.map(tracks_now, fn {{device_id, id}, t} ->
      vz = Map.get(t, :vz, 0.0)
      speed = :math.sqrt(t.vx * t.vx + t.vy * t.vy + vz * vz)
      age = now - t.last_seen
      opacity = max(0.0, 1.0 - age / @fade_ms)

      %{
        device_id: device_id,
        id: id,
        label: track_label(device_id, id, selected),
        x: t.x,
        y: t.y,
        z: t.z,
        speed: speed,
        opacity: opacity,
        color: sensor_color(device_id),
        letter: device_letter(device_id)
      }
    end)
  end

  defp apply_detection_list_mode(tracks, _devices, :by_proximity),
    do: group_by_proximity(tracks)

  defp apply_detection_list_mode(tracks, devices, _mode),
    do: group_by_sensor(tracks, devices)

  defp group_by_sensor(tracks, devices) do
    by_device = Enum.group_by(tracks, & &1.device_id)

    devices
    |> Enum.map(fn d ->
      items =
        by_device
        |> Map.get(d.device_id, [])
        |> Enum.sort_by(& &1.id)

      if items == [] do
        nil
      else
        %{
          type: :sensor_group,
          device_id: d.device_id,
          letter: device_letter(d.device_id),
          color: sensor_color(d.device_id),
          items: items
        }
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp group_by_proximity(tracks) do
    tracks
    |> cluster_tracks(@proximity_cluster_m)
    |> Enum.with_index(1)
    |> Enum.map(fn {items, idx} ->
      centroid = cluster_centroid(items)
      span_m = cluster_span(items)

      %{
        type: :cluster,
        id: idx,
        span_m: span_m,
        items: Enum.sort_by(items, &dist_xy(&1, centroid))
      }
    end)
    |> Enum.sort_by(
      fn cluster ->
        {-length(cluster.items), cluster_dist_origin(cluster_centroid(cluster.items))}
      end,
      :asc
    )
    |> Enum.with_index(1)
    |> Enum.map(fn {cluster, idx} -> %{cluster | id: idx} end)
  end

  defp cluster_tracks(tracks, threshold) do
    indexed = Enum.with_index(tracks)

    parent =
      Enum.reduce(0..(length(tracks) - 1), %{}, fn i, acc ->
        Map.put(acc, i, i)
      end)

    parent =
      Enum.reduce(indexed, parent, fn {t1, i}, acc ->
        Enum.reduce(indexed, acc, fn {t2, j}, acc2 ->
          if i < j and dist_xy(t1, t2) <= threshold do
            union_parent(acc2, i, j)
          else
            acc2
          end
        end)
      end)

    indexed
    |> Enum.group_by(fn {_, i} -> elem(find_parent(parent, i), 0) end, fn {t, _} -> t end)
    |> Map.values()
  end

  defp find_parent(parent, i) do
    case Map.fetch!(parent, i) do
      ^i ->
        {i, parent}

      p ->
        {root, parent} = find_parent(parent, p)
        {root, Map.put(parent, i, root)}
    end
  end

  defp union_parent(parent, i, j) do
    {root_i, parent} = find_parent(parent, i)
    {root_j, parent} = find_parent(parent, j)
    Map.put(parent, root_j, root_i)
  end

  defp cluster_centroid(items) do
    n = length(items)

    %{
      x: Enum.sum(Enum.map(items, & &1.x)) / n,
      y: Enum.sum(Enum.map(items, & &1.y)) / n,
      z: Enum.sum(Enum.map(items, & &1.z)) / n
    }
  end

  defp cluster_span(items) do
    case items do
      [_] ->
        0.0

      _ ->
        items
        |> pairs()
        |> Enum.map(fn {a, b} -> dist_xy(a, b) end)
        |> Enum.max()
    end
  end

  defp cluster_dist_origin(%{x: x, y: y}) do
    :math.sqrt(x * x + y * y)
  end

  defp pairs([_]), do: []

  defp pairs(items) do
    for {a, i} <- Enum.with_index(items),
        {b, j} <- Enum.with_index(items),
        i < j,
        do: {a, b}
  end

  defp dist_xy(%{x: x1, y: y1}, %{x: x2, y: y2}) do
    dx = x1 - x2
    dy = y1 - y2
    :math.sqrt(dx * dx + dy * dy)
  end

  defp build_trail_segments(samples, now, hue, min_x, max_x, min_y, max_y) do
    samples
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [s1, s2] ->
      %{
        x1: world_to_svg_x(s1.x, min_x, max_x),
        y1: world_to_svg_y(s1.y, min_y, max_y),
        x2: world_to_svg_x(s2.x, min_x, max_x),
        y2: world_to_svg_y(s2.y, min_y, max_y),
        color: trail_color(hue, now - s2.ts)
      }
    end)
  end

  defp group_samples_by_key(samples, trail_cutoff) do
    samples
    |> Enum.filter(&(&1.ts >= trail_cutoff))
    |> Enum.group_by(&{&1.device_id, &1.id})
    |> Map.new(fn {key, ss} -> {key, Enum.sort_by(ss, & &1.ts)} end)
  end

  ## Ruler view model

  defp build_ruler(min_x, max_x, min_y, max_y) do
    origin_x = world_to_svg_x(0.0, min_x, max_x)
    origin_y = world_to_svg_y(0.0, min_y, max_y)

    %{
      x_axis_visible: min_y <= 0.0 and max_y >= 0.0,
      y_axis_visible: min_x <= 0.0 and max_x >= 0.0,
      origin_x: origin_x,
      origin_y: origin_y,
      ticks:
        axis_ticks(min_x, max_x, origin_y, :horizontal) ++
          axis_ticks(min_y, max_y, origin_x, :vertical)
    }
  end

  defp axis_ticks(lo_w, hi_w, axis_pos, orientation) do
    lo_dm = ceil(lo_w * 10)
    hi_dm = floor(hi_w * 10)

    if lo_dm > hi_dm do
      []
    else
      Enum.map(lo_dm..hi_dm//1, fn dm ->
        major? = rem(dm, 10) == 0
        len = if major?, do: @major_tick_len, else: @minor_tick_len
        half = len / 2
        world = dm / 10

        case orientation do
          :horizontal ->
            pos = world_to_svg_x(world, lo_w, hi_w)
            %{x1: pos, y1: axis_pos - half, x2: pos, y2: axis_pos + half, major?: major?}

          :vertical ->
            pos = world_to_svg_y(world, lo_w, hi_w)
            %{x1: axis_pos - half, y1: pos, x2: axis_pos + half, y2: pos, major?: major?}
        end
      end)
    end
  end

  defp world_to_svg_x(x, min_x, max_x), do: scale(x, min_x, max_x, @vb)

  defp world_to_svg_y(y, min_y, max_y), do: @vb - scale(y, min_y, max_y, @vb)

  defp scale(value, lo, hi, span) do
    (value - lo) / (hi - lo) * span
  end

  defp clamp(v, lo, _hi) when v < lo, do: lo
  defp clamp(v, _lo, hi) when v > hi, do: hi
  defp clamp(v, _lo, _hi), do: v

  defp radius_for_z(z) do
    z = clamp(z, @z_min, @z_max)
    @r_max - (z - @z_min) / (@z_max - @z_min) * (@r_max - @r_min)
  end

  # Stable per-sensor hue/color (independent of track id) so each sensor's
  # placement, coverage and detections share one tint.
  defp sensor_hue(device_id), do: Enum.at(@hues, rem(device_id * 7, length(@hues)))

  defp sensor_color(device_id),
    do: "hsl(#{sensor_hue(device_id)}, #{@body_saturation}%, #{@body_lightness}%)"

  defp sensor_placement_color(device_id, true),
    do:
      "hsl(#{sensor_hue(device_id)}, #{@sensor_detecting_saturation}%, #{@sensor_detecting_lightness}%)"

  defp sensor_placement_color(device_id, false), do: sensor_color(device_id)

  defp trail_color(hue, age_ms) do
    age_fraction = min(1.0, age_ms / @trail_ms)
    lightness = @trail_l_near + age_fraction * (@trail_l_far - @trail_l_near)
    "hsl(#{hue}, #{@body_saturation}%, #{round(lightness)}%)"
  end

  ## Mock mode helpers

  defp mock_source?(mode), do: mode in [:exact, :fuzzy]

  defp source_mode_options(live_available) do
    [
      {"off", "Off", false},
      {"live", "Live", not live_available},
      {"exact", "Mock · Exact", false},
      {"fuzzy", "Mock · Fuzzy", false}
    ]
  end

  defp source_mode_button_title("live", true), do: "No radar hardware bound on this host"
  defp source_mode_button_title(_value, _disabled?), do: nil

  defp parse_source_mode("live"), do: :live
  defp parse_source_mode("exact"), do: :exact
  defp parse_source_mode("fuzzy"), do: :fuzzy
  defp parse_source_mode("off"), do: :off
  defp parse_source_mode(_), do: :off

  defp parse_degree(v) when is_binary(v) do
    case Float.parse(v) do
      {deg, _} -> {:ok, deg}
      :error -> :error
    end
  end

  defp safe_max_people, do: max(Radar.max_people(), 1)

  defp safe_entropy, do: Radar.entropy()

  defp subscribe_world, do: Phoenix.PubSub.subscribe(Octopus.PubSub, World.world_topic())
  defp unsubscribe_world, do: Phoenix.PubSub.unsubscribe(Octopus.PubSub, World.world_topic())

  ## Sensor status helpers

  defp build_sensor_statuses(devices) do
    Map.new(devices, fn d -> {d.device_id, Radar.sensor_status(d.device_id)} end)
  end

  # Multi-line hover text carrying each sensor's status and configuration
  # (the data that used to live in the now-removed stats row).
  defp sensor_tooltip(d, status) do
    Enum.join(
      [
        "Sensor #{device_letter(d.device_id)} (#{d.port})",
        "Status: #{sensor_status_label(status)}",
        "Pose: #{d.angle_deg}° @ #{d.distance_cm} cm · rotation #{d.rotation_deg}°",
        "Range: #{d.range_cm} cm · Height: #{d.height_cm} cm",
        "Sensitivity: #{10 - d.sensitivity}/9",
        "Click to toggle active/inactive"
      ],
      "\n"
    )
  end

  defp sensor_status_class(:inactive),
    do: "bg-white text-gray-600 border border-gray-300 hover:bg-gray-50"

  defp sensor_status_class(:unavailable),
    do: "bg-red-500 text-white border-red-600 hover:bg-red-600"

  defp sensor_status_class(:initializing),
    do: "bg-amber-400 text-white border-amber-500 hover:bg-amber-500"

  defp sensor_status_class(:probing),
    do: "bg-cyan-500 text-white border-cyan-600 hover:bg-cyan-600"

  defp sensor_status_class(:working),
    do: "bg-green-500 text-white border-green-600 hover:bg-green-600"

  defp sensor_status_class(:stale),
    do: "bg-orange-500 text-white border-orange-600 hover:bg-orange-600"

  defp sensor_status_class(:resetting),
    do: "bg-gray-900 text-white border-gray-800 hover:bg-gray-800"

  defp sensor_status_class(_), do: sensor_status_class(:unavailable)

  defp sensor_status_label(:inactive), do: "Inactive"
  defp sensor_status_label(:unavailable), do: "Unavailable"
  defp sensor_status_label(:initializing), do: "Initializing"
  defp sensor_status_label(:probing), do: "Probing"
  defp sensor_status_label(:working), do: "Working"
  defp sensor_status_label(:stale), do: "No Data"
  defp sensor_status_label(:resetting), do: "Resetting"
  defp sensor_status_label(_), do: "Unknown"

  ## Formatting helpers

  defp fmt_f(v) when is_integer(v), do: Integer.to_string(v)
  defp fmt_f(v) when is_float(v), do: :erlang.float_to_binary(v, decimals: 2)

  defp fmt_m(v) when is_integer(v), do: Integer.to_string(v) <> " m"
  defp fmt_m(v) when is_float(v), do: :erlang.float_to_binary(v, decimals: 2) <> " m"
end
