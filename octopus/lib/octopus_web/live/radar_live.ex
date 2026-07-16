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

  use OctopusWeb, {:live_view, log: false}

  require Logger

  alias Octopus.Installation
  alias Octopus.Radar
  alias Octopus.Radar.{Frame, Track, TrackMerge, Transform}
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

  # High-frequency data (radar frames from every sensor + mock-world ticks)
  # arrives dozens of times per second. Rather than run the expensive
  # `rebuild_view/1` (and push a full SVG diff) on each message — which
  # saturates the LiveView process and makes UI events feel laggy — incoming
  # data only updates raw state and requests a render. A single coalesced
  # re-render then runs at most once per this interval (~15 fps).
  @render_interval_ms 66

  # Position change below this threshold (meters, 3D) is treated as stationary
  # for dump analysis — filters radar jitter from true movement.
  @position_stationary_threshold_m 0.05

  # Lightness range for the trail's per-segment color. The newest
  # segment (closest to the body circle) is rendered at `@trail_l_near`
  # and brightens linearly toward `@trail_l_far` for the oldest segment.
  @trail_l_near 60
  @trail_l_far 95

  # SVG viewBox extent. The template hardcodes the matching string. The
  # canvas wrapper keeps a square aspect ratio so circles always render
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

  # Tracks whose XY speed is below this threshold (m/s) are treated as
  # stationary and excluded from the visualization and gravity computation.
  @velocity_min_m_s 0.05

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
    view_settings = Radar.view_settings()
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

    {:ok,
     socket
     |> assign(:radar_configured, Radar.configured?())
     |> assign(:ui_mode, :developer)
     |> assign(:live_available, Radar.live_available?())
     |> assign(:layout_devices, layout_devices)
     |> assign(:devices, devices)
     |> assign(:radial_layout, Radar.radial_layout?())
     |> assign(:angle_offset_deg, round(Radar.angle_offset_deg()))
     |> assign(:rotation_target, "global")
     |> assign(:rotation_slider_seq, 0)
     |> assign(:sensor_installation_angles, Radar.sensor_installation_angles())
     |> assign(:north_panel, view_settings.north_panel)
     |> assign(:sensor_statuses, build_sensor_statuses(devices))
     |> assign(:sensitivity_level, Radar.sensitivity_level())
     |> assign(:source_mode, source_mode)
     |> assign(:max_people, safe_max_people())
     |> assign(:max_people_limit, Radar.max_people_limit())
     |> assign(:max_people_applying, false)
     |> assign(:max_people_applying_until, 0)
     |> assign(:entropy, safe_entropy())
     |> assign(:manual_tracking, Radar.manual_tracking?())
     |> assign(:world_radius, world_radius)
     |> assign(:platform_radius, platform_radius)
     |> assign(:ring_layout, ring_layout)
     |> assign(:world_objects, [])
     |> assign(:visuals, view_settings.visuals)
     |> assign(:detection_list_mode, view_settings.detection_list_mode)
     |> assign(:coords_frame, view_settings.coords_frame)
     |> assign(:render_scheduled, false)
     |> assign(:bounds_mode, view_settings.bounds_mode)
     |> assign(:clutter_filter, view_settings.clutter_filter)
     |> assign(:track_fusion, Radar.track_fusion_enabled?())
     |> assign(:track_fusion_radius_m, Radar.track_fusion_radius_m())
     |> assign(:gravity_fuse, Radar.gravity_fuse_enabled?())
     |> assign(:gravity_near_dist_m, Radar.gravity_near_dist_m())
     |> assign(:gravity_far_dist_m, Radar.gravity_far_dist_m())
     |> assign(:gravity_max_pct, Radar.gravity_max_pct())
     |> assign(:static_bounds, world_bounds(world_radius))
     |> reset_radar_state()}
  end


  # The canvas always frames the entire simulated world (in every mode) so the
  # world border, the sensors and their coverage, and the detections all share
  # one fixed, fully-visible frame. The extent is padded slightly past the
  # world radius so the border circle isn't clipped at the canvas edge.
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
    case Installation.ring_layout_m() do
      %{num_panels: count, panel_width_m: width_m, panel_depth_m: depth_m} ->
        %{enabled: true, count: count, width_m: width_m, depth_m: depth_m}

      nil ->
        %{enabled: false, count: 1, width_m: 0.0, depth_m: 0.0}
    end
  end

  # Sensor → letter mapping for labels. Device 1 = "A", 2 = "B", etc.
  defp device_letter(device_id) when is_integer(device_id) do
    <<?A + rem(device_id - 1, 26)>>
  end

  @impl true
  # Toggle between static (canvas matches the sensor's configured X/Y
  # rectangle) and auto (grow-only bounds derived from observed samples).
  def handle_event("toggle_bounds_mode", params, socket) do
    new_mode = if params["auto"] == "true", do: :auto, else: :static
    Radar.set_bounds_mode(new_mode)
    {:noreply, socket}
  end

  def handle_event("toggle_ui_mode", %{"mode" => mode}, socket) do
    ui_mode = if mode == "live", do: :live, else: :developer
    {:noreply, assign(socket, :ui_mode, ui_mode)}
  end

  def handle_event("set_sensitivity", %{"sensitivity_level" => level_str}, socket) do
    with {level, ""} <- Integer.parse(level_str),
         true <- level in 1..9 do
      Radar.set_sensitivity_level(level)

      {:noreply, reset_radar_state(socket)}
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
        {:noreply, socket}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("set_entropy", %{"entropy" => v}, socket) do
    case Integer.parse(v) do
      {n, _} ->
        Radar.set_entropy(n)
        {:noreply, socket}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("toggle_manual_tracking", _params, socket) do
    Radar.set_manual_tracking(not Radar.manual_tracking?())
    {:noreply, socket}
  end

  # Pointer moved over the map: map the viewBox coordinates (0..@vb) reported by
  # the JS hook into world meters using the current (padded) render bounds, and
  # drive the single manually-tracked object.
  def handle_event("manual_point", %{"x" => vbx, "y" => vby}, socket) do
    if socket.assigns.manual_tracking do
      a = socket.assigns
      {min_x, max_x} = pad_range(a.min_x, a.max_x)
      {min_y, max_y} = pad_range(a.min_y, a.max_y)
      {wx, wy} = svg_to_world(to_f(vbx), to_f(vby), min_x, max_x, min_y, max_y)
      Radar.set_manual_point(wx, wy)
    end

    {:noreply, socket}
  end

  def handle_event("manual_clear", _params, socket) do
    if socket.assigns.manual_tracking, do: Radar.clear_manual_point()
    {:noreply, socket}
  end

  def handle_event("set_sensor_rotation", params, socket) do
    target =
      if rotation_target_changed?(params) do
        Map.get(params, "rotation_target", socket.assigns.rotation_target)
      else
        socket.assigns.rotation_target
      end
      |> normalize_rotation_target()

    socket = assign(socket, :rotation_target, target)

    stale_slider? =
      case parse_rotation_seq(params["rotation_seq"]) do
        {:ok, seq} -> seq < socket.assigns.rotation_slider_seq
        :error -> false
      end

    socket =
      cond do
        rotation_target_changed?(params) ->
          socket

        not rotation_deg_changed?(params) ->
          socket

        stale_slider? ->
          socket

        true ->
          socket =
            case parse_rotation_seq(params["rotation_seq"]) do
              {:ok, seq} -> assign(socket, :rotation_slider_seq, seq)
              :error -> socket
            end

          apply_rotation_deg(socket, target, params["rotation_deg"])
      end

    {:noreply, maybe_push_rotation_slider_sync(socket, params)}
  end

  def handle_event("set_detection_list_mode", %{"mode" => mode}, socket) do
    mode_atom =
      case mode do
        "proximity" -> :by_proximity
        _ -> :by_sensor
      end

    Radar.set_detection_list_mode(mode_atom)
    {:noreply, socket}
  end

  # Both x/y/z and the sensor-local lx/ly/lz are always precomputed on each
  # detection, so switching frames only changes which the template shows — no
  # rebuild needed.
  def handle_event("toggle_coords_frame", _params, socket) do
    Radar.toggle_coords_frame()
    {:noreply, socket}
  end

  def handle_event("toggle_visual", %{"feature" => feature}, socket) do
    key = String.to_existing_atom(feature)
    Radar.toggle_visual(key)
    {:noreply, socket}
  rescue
    ArgumentError -> {:noreply, socket}
  end

  def handle_event("toggle_clutter_filter", _params, socket) do
    Radar.toggle_clutter_filter()
    {:noreply, socket}
  end

  def handle_event("toggle_track_fusion", _params, socket) do
    Radar.toggle_track_fusion()
    {:noreply, socket}
  end

  def handle_event("toggle_gravity_fuse", _params, socket) do
    new_val = Radar.toggle_gravity_fuse()
    {:noreply, assign(socket, :gravity_fuse, new_val)}
  end

  def handle_event("set_gravity_distances", params, socket) do
    near = parse_float(params["near_dist_m"], socket.assigns.gravity_near_dist_m)
    far = parse_float(params["far_dist_m"], socket.assigns.gravity_far_dist_m)
    Radar.set_gravity_distances(near, far)
    {:noreply, socket |> assign(:gravity_near_dist_m, near) |> assign(:gravity_far_dist_m, far)}
  end

  def handle_event("set_gravity_levels", params, socket) do
    max_g = parse_float(params["max_gravity_pct"], socket.assigns.gravity_max_pct)
    Radar.set_gravity_max(max_g)
    {:noreply, assign(socket, :gravity_max_pct, max_g)}
  end

  def handle_event("set_track_fusion_radius", %{"radius_m" => radius_str}, socket) do
    case Float.parse(radius_str) do
      {radius_m, _} -> Radar.set_track_fusion_radius_m(radius_m)
      :error -> :ok
    end

    {:noreply, socket}
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

        {:noreply,
         socket
         |> assign(:sensor_statuses, statuses)
         |> reset_radar_state()}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("reinitialize", _params, socket) do
    Enum.each(socket.assigns.devices, &Radar.reinitialize(&1.device_id))
    Radar.reset_clutter_filter()
    {:noreply, reset_radar_state(socket)}
  end

  def handle_event("dump_detections", _params, socket) do
    dump_id = dump_detections_id()
    json = generate_detections_dump_json(socket.assigns, dump_id)
    Logger.info("RADAR-DETECTIONS-DUMP[#{dump_id}] #{json}")
    {:noreply, socket}
  end

  def handle_event("dump_track_history", params, socket) do
    with {device_id, ""} <- Integer.parse(params["device_id"]),
         {track_id, ""} <- Integer.parse(params["track_id"]) do
      dump_track_history(device_id, track_id)
    end

    {:noreply, socket}
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

  def handle_info({:sensitivity_level_changed, level}, socket) do
    {:noreply,
     socket
     |> assign(:sensitivity_level, level)
     |> assign(:devices, update_devices_sensitivity(socket.assigns.devices, level))}
  end

  def handle_info({:view_settings_changed, settings}, socket) do
    {:noreply, apply_view_settings(socket, settings)}
  end

  def handle_info({:mock_settings_changed, settings}, socket) do
    {:noreply, apply_mock_settings(socket, settings)}
  end

  def handle_info({:track_fusion_changed, %{enabled?: enabled?, radius_m: radius_m}}, socket) do
    {:noreply,
     socket
     |> assign(:track_fusion, enabled?)
     |> assign(:track_fusion_radius_m, radius_m)
     |> rebuild_view()}
  end

  def handle_info({:panel_gravity_settings_changed, settings}, socket) do
    socket =
      socket
      |> assign(:gravity_fuse, Map.get(settings, :fuse_people, socket.assigns.gravity_fuse))
      |> assign(:gravity_near_dist_m, Map.get(settings, :near_dist_m, socket.assigns.gravity_near_dist_m))
      |> assign(:gravity_far_dist_m, Map.get(settings, :far_dist_m, socket.assigns.gravity_far_dist_m))
      |> assign(:gravity_max_pct, Map.get(settings, :max_gravity_pct, socket.assigns.gravity_max_pct))

    {:noreply, socket}
  end

  def handle_info({:pose_tweak_changed, tweak}, socket) do
    devices = Radar.devices() |> Enum.filter(& &1.enabled)

    {:noreply,
     socket
     |> assign(:layout_devices, Radar.planned_devices())
     |> assign(:devices, devices)
     |> assign(:angle_offset_deg, round(Map.get(tweak, :angle_offset_deg, 0)))
     |> assign(:sensor_installation_angles, Map.get(tweak, :sensor_installation_angles, %{}))
     |> rebuild_view()}
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
     |> schedule_render()}
  end

  @impl true
  def handle_info({:radar_frame, device_id, %Frame{} = frame}, socket) do
    {:noreply, ingest_frame(socket, device_id, frame)}
  end

  def handle_info(:render, socket) do
    {:noreply, socket |> assign(:render_scheduled, false) |> rebuild_view()}
  end

  def handle_info({:platform_radius_m, value}, socket) do
    {:noreply, socket |> assign(:platform_radius, value) |> rebuild_view()}
  end

  # The Sim3D topic carries other parameter broadcasts too; ignore them.
  def handle_info(_msg, socket), do: {:noreply, socket}

  defp update_devices_sensitivity(devices, level) do
    Enum.map(devices, fn device -> %{device | sensitivity_level: level} end)
  end

  defp apply_view_settings(socket, settings) do
    socket
    |> assign(:north_panel, settings.north_panel)
    |> assign(:detection_list_mode, settings.detection_list_mode)
    |> assign(:coords_frame, settings.coords_frame)
    |> assign(:visuals, settings.visuals)
    |> assign(:bounds_mode, settings.bounds_mode)
    |> assign(:clutter_filter, settings.clutter_filter)
    |> apply_clutter_filter_to_tracks_now(settings.clutter_filter)
    |> apply_bounds_for_mode()
    |> rebuild_view()
  end

  defp apply_clutter_filter_to_tracks_now(socket, true) do
    tracks_now =
      Map.filter(socket.assigns.tracks_now, fn {{device_id, track_id}, _} ->
        Radar.clutter_filter_track_qualified?(device_id, track_id)
      end)

    assign(socket, :tracks_now, tracks_now)
  end

  defp apply_clutter_filter_to_tracks_now(socket, _enabled), do: socket

  defp apply_mock_settings(socket, %{max_people: target, entropy: entropy, manual_tracking: manual_tracking}) do
    applying? = length(socket.assigns.world_objects) != target
    until = System.monotonic_time(:millisecond) + @apply_min_ms

    socket
    |> assign(:max_people, target)
    |> assign(:entropy, entropy |> max(0) |> min(100))
    |> assign(:manual_tracking, manual_tracking)
    |> assign(:max_people_applying, applying?)
    |> assign(:max_people_applying_until, until)
  end

  defp handle_source_mode_changed(socket, mode) do
    if connected?(socket) do
      if mock_source?(mode), do: subscribe_world(), else: unsubscribe_world()
    end

    devices = Radar.devices() |> Enum.filter(& &1.enabled)
    view_settings = Radar.view_settings()

    Radar.reset_clutter_filter()

    {:noreply,
     socket
     |> assign(:source_mode, mode)
     |> assign(:layout_devices, Radar.planned_devices())
     |> assign(:devices, devices)
     |> assign(:max_people, safe_max_people())
     |> assign(:max_people_applying, false)
     |> assign(:entropy, safe_entropy())
     |> assign(:manual_tracking, Radar.manual_tracking?())
     |> assign(:bounds_mode, view_settings.bounds_mode)
     |> assign(:north_panel, view_settings.north_panel)
     |> assign(:detection_list_mode, view_settings.detection_list_mode)
     |> assign(:coords_frame, view_settings.coords_frame)
     |> assign(:visuals, view_settings.visuals)
     |> assign(:clutter_filter, view_settings.clutter_filter)
     |> assign(:world_objects, [])
     |> assign(:sensor_statuses, build_sensor_statuses(devices))
     |> assign(:sensitivity_level, Radar.sensitivity_level())
     |> assign(:static_bounds, world_bounds(socket.assigns.world_radius))
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
    |> assign(:fusion_links, [])
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

  defp empty_ruler,
    do: %{x_axis_visible: false, y_axis_visible: false, origin_x: 0, origin_y: 0, ticks: []}

  defp ingest_frame(socket, device_id, %Frame{tracks: tracks, frame_number: frame_number}) do
    now = System.monotonic_time(:millisecond)
    cutoff = now - @window_ms
    fade_cutoff = now - @fade_ms

    tracks_now =
      tracks
      |> Enum.filter(fn t -> :math.sqrt(t.vx * t.vx + t.vy * t.vy) >= @velocity_min_m_s end)
      |> Enum.reduce(socket.assigns.tracks_now, fn %Track{} = t, acc ->
        key = {device_id, t.id}
        prev = Map.get(acc, key)

        position_last_changed =
          if prev == nil or track_position_moved?(prev, t) do
            now
          else
            prev.position_last_changed
          end

        Map.put(acc, key, %{
          device_id: device_id,
          id: t.id,
          x: t.x,
          y: t.y,
          z: t.z,
          vx: t.vx,
          vy: t.vy,
          vz: t.vz,
          last_seen: now,
          first_seen: if(prev, do: prev.first_seen, else: now),
          position_last_changed: position_last_changed
        })
      end)
      |> Enum.reject(fn {_key, t} -> t.last_seen < fade_cutoff end)
      |> Map.new()

    new_samples =
      Enum.map(tracks, fn %Track{id: id, x: x, y: y, z: z} ->
        %{ts: now, device_id: device_id, id: id, x: x, y: y, z: z}
      end)

    samples =
      (new_samples ++ socket.assigns.samples)
      |> Enum.filter(&(&1.ts >= cutoff))

    a = socket.assigns

    {min_x, max_x, min_y, max_y} = update_xy_bounds(a, new_samples)
    {min_z, max_z} = grow_bounds(new_samples, a.min_z, a.max_z, :z)

    socket
    |> assign(:samples, samples)
    |> assign(:tracks_now, tracks_now)
    |> assign(:last_frame_number, frame_number)
    |> assign(:min_x, min_x)
    |> assign(:max_x, max_x)
    |> assign(:min_y, min_y)
    |> assign(:max_y, max_y)
    |> assign(:min_z, min_z)
    |> assign(:max_z, max_z)
    |> schedule_render()
  end

  # Coalesce high-frequency data updates into at most one re-render per
  # `@render_interval_ms`. If a render is already pending we just leave the
  # freshly-updated state in place; the scheduled tick will pick it up.
  defp schedule_render(%{assigns: %{render_scheduled: true}} = socket), do: socket

  defp schedule_render(socket) do
    Process.send_after(self(), :render, @render_interval_ms)
    assign(socket, :render_scheduled, true)
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
        max_y: max_y
      })

    fusion_links = build_fusion_links(view_targets)

    ruler = build_ruler(min_x, max_x, min_y, max_y)

    active_devices = Enum.filter(a.devices, &Radar.sensor_active?(&1.device_id))
    active_ids = MapSet.new(active_devices, & &1.device_id)

    range_indicators =
      build_range_indicators(
        a.layout_devices,
        active_ids,
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
        a.detection_list_mode
      )

    socket
    |> assign(:view_targets, view_targets)
    |> assign(:fusion_links, fusion_links)
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
  defp build_range_indicators(layout_devices, active_ids, tracks_now, min_x, max_x, min_y, max_y) do
    detecting = devices_with_detections(tracks_now)

    Enum.map(layout_devices, fn device ->
      active? = MapSet.member?(active_ids, device.device_id)
      detecting? = active? and MapSet.member?(detecting, device.device_id)
      range_indicator(device, active?, detecting?, min_x, max_x, min_y, max_y)
    end)
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

  # LED displays on the installation ring (+Y = north). Geometry comes from
  # `Installation.panel_positions_m/1` — this only projects meters → SVG.
  defp build_ring_panels(_radius_m, ring_layout, north_panel, min_x, max_x, min_y, max_y) do
    width_m = ring_layout.width_m
    depth_m = ring_layout.depth_m

    positions =
      Installation.panel_positions_m(
        reference: :body_center,
        north_panel: north_panel,
        label_clearance_m: 0.25
      )

    Enum.map(positions, fn p ->
      %{
        number: p.panel,
        cx: world_to_svg_x(p.x, min_x, max_x),
        cy: world_to_svg_y(p.y, min_y, max_y),
        label_cx: world_to_svg_x(p.label_x, min_x, max_x),
        label_cy: world_to_svg_y(p.label_y, min_y, max_y),
        half_w: width_m / (max_x - min_x) * @vb / 2,
        half_h: depth_m / (max_y - min_y) * @vb / 2,
        rotation: p.theta_deg
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
    Installation.sensor_mount_m(device.angle_deg, device.distance_cm)
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
    <%= if not @radar_configured do %>
      <div class="p-4">
        <div class="alert alert-info">
          <span>
            Add a <code>:radar</code> block to the active installation module to use radar.
          </span>
        </div>
      </div>
    <% else %>
      <div class={["flex w-full h-[calc(100vh-2.5rem)] min-h-0",
                   if(@ui_mode == :developer, do: "flex-row flex-nowrap items-stretch", else: "flex-col")]}>
        <%= if @ui_mode == :live do %>
          <div class="shrink-0 flex flex-row items-center gap-6 px-4 py-2 border-b border-base-300 bg-base-100">
            <div class="flex items-center gap-2">
              <p class="text-xs font-semibold opacity-70 whitespace-nowrap">Source</p>
              <div class="flex flex-wrap gap-1" id="radar-source-mode-live">
                <%= for {value, label, disabled?} <- source_mode_options(@live_available) do %>
                  <button
                    type="button"
                    phx-click="set_source_mode"
                    phx-value-mode={value}
                    disabled={disabled?}
                    title={source_mode_button_title(value, disabled?)}
                    class={[
                      "btn btn-sm",
                      if(Atom.to_string(@source_mode) == value, do: "btn-primary", else: "btn-outline"),
                      disabled? && "btn-disabled"
                    ]}
                  >
                    {label}
                  </button>
                <% end %>
              </div>
            </div>
            <div class="flex items-center gap-2">
              <p class="text-xs font-semibold opacity-70 whitespace-nowrap">Sensors</p>
              <div class="flex flex-nowrap gap-1">
                <%= for d <- @devices do %>
                  <button
                    type="button"
                    phx-click="toggle_sensor"
                    phx-value-device_id={d.device_id}
                    title={sensor_tooltip(d, @sensor_statuses[d.device_id])}
                    class={[
                      "btn btn-sm font-mono px-2",
                      sensor_status_class(@sensor_statuses[d.device_id])
                    ]}
                  >
                    {device_letter(d.device_id)}
                  </button>
                <% end %>
              </div>
            </div>
          </div>
        <% end %>
        <%= if @ui_mode == :developer do %>
        <div class="w-64 shrink-0 h-full overflow-y-auto flex flex-col gap-3 p-3 border-r border-base-300 bg-base-100">
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
            <div class="flex items-center justify-between gap-2">
              <label for="radar-coords-frame" class="text-xs font-semibold opacity-70">
                Local coordinates
              </label>
              <input
                id="radar-coords-frame"
                type="checkbox"
                class="toggle toggle-sm toggle-primary"
                checked={@coords_frame == :local}
                phx-click="toggle_coords_frame"
              />
            </div>
            <button
              id="radar-dump-detections"
              type="button"
              class="btn btn-outline btn-sm w-full"
              phx-click="dump_detections"
              title="Write current detections, sensor poses, and layout context to the server log as JSON (RADAR-DETECTIONS-DUMP)"
            >
              Dump detections to log
            </button>
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
                        class="text-xs font-mono rounded px-2 py-1.5 bg-base-200/80 border border-base-300/60 cursor-pointer hover:bg-base-300/80"
                        style={"opacity: #{fmt_f(item.opacity)}"}
                        phx-click="dump_track_history"
                        phx-value-device_id={item.device_id}
                        phx-value-track_id={item.id}
                        title="Dump last 10s movement history to server log"
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
                          <%= if @coords_frame == :local do %>
                            x {fmt_m(item.lx)} · y {fmt_m(item.ly)} · z {fmt_m(item.lz)}
                          <% else %>
                            x {fmt_m(item.x)} · y {fmt_m(item.y)} · z {fmt_m(item.z)}
                          <% end %>
                        </div>
                      </li>
                    <% end %>
                  </ul>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
        <% end %>

        <div
          class={["min-w-0 min-h-0 flex items-center justify-center overflow-hidden bg-base-200 relative",
                  if(@ui_mode == :developer, do: "flex-1 h-full", else: "flex-1 w-full")]}
          style="container-type: size;"
        >
          <div class="absolute top-2 right-2 z-10 join shadow">
            <button
              type="button"
              class={["btn btn-xs join-item", if(@ui_mode == :developer, do: "btn-neutral", else: "btn-ghost opacity-50 hover:opacity-100")]}
              phx-click="toggle_ui_mode"
              phx-value-mode="developer"
              title="Developer view"
            >Dev</button>
            <button
              type="button"
              class={["btn btn-xs join-item", if(@ui_mode == :live, do: "btn-neutral", else: "btn-ghost opacity-50 hover:opacity-100")]}
              phx-click="toggle_ui_mode"
              phx-value-mode="live"
              title="Live view"
            >Live</button>
          </div>
          <div style="width: min(100cqw, 100cqh); height: min(100cqw, 100cqh); aspect-ratio: 1; flex-shrink: 0;">
            <svg
              id="radar-map"
              viewBox="0 0 1000 1000"
              class={["w-full h-full", @manual_tracking && "cursor-crosshair"]}
              phx-hook="RadarManualPointer"
              data-active={to_string(@manual_tracking)}
            >
                      <%!-- Transparent backdrop so pointer events (cursor
                           tracking) fire across the whole map, not just over
                           drawn shapes. --%>
                      <rect x="0" y="0" width="1000" height="1000" fill="transparent" />

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

                      <%!-- Fusion links: connects detections the fusion layer folded into one combined object --%>
                      <%= if @visuals.detections and @track_fusion do %>
                        <%= for link <- @fusion_links do %>
                          <line
                            x1={fmt_f(link.x1)}
                            y1={fmt_f(link.y1)}
                            x2={fmt_f(link.x2)}
                            y2={fmt_f(link.y2)}
                            stroke="#f59e0b"
                            stroke-width="2"
                            stroke-dasharray="4 3"
                          />
                        <% end %>
                      <% end %>

                      <%!-- Detections --%>
                      <%= if @visuals.detections do %>
                        <%= for v <- @view_targets do %>
                          <g
                            opacity={fmt_f(v.opacity)}
                            phx-click="dump_track_history"
                            phx-value-device_id={v.device_id}
                            phx-value-track_id={v.track_id}
                            style="cursor: pointer"
                          >
                            <title>{detection_tooltip(v)}</title>
                            <%= if v.merged? do %>
                              <circle
                                cx={fmt_f(v.cx)}
                                cy={fmt_f(v.cy)}
                                r={fmt_f((if @visuals.height_size, do: v.radius, else: @detection_fixed_r) + 10)}
                                fill="none"
                                stroke="#f59e0b"
                                stroke-width="2.5"
                                stroke-dasharray="4 3"
                              >
                                <title>Fused with another sensor's detection of the same object</title>
                              </circle>
                            <% end %>
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
                            <%= if v.merged? do %>
                              <%= for slice <- pie_slices(
                                v.cx,
                                v.cy,
                                if(@visuals.height_size, do: v.radius, else: @detection_fixed_r),
                                v.sensor_ids
                              ) do %>
                                <path d={slice.d} fill={slice.color} fill-opacity="0.5" stroke={slice.color} stroke-width="1" />
                              <% end %>
                              <circle
                                cx={fmt_f(v.cx)}
                                cy={fmt_f(v.cy)}
                                r={fmt_f(if @visuals.height_size, do: v.radius, else: @detection_fixed_r)}
                                fill="none"
                                stroke="black"
                                stroke-width="1"
                                stroke-opacity="0.3"
                              />
                            <% else %>
                              <circle
                                cx={fmt_f(v.cx)}
                                cy={fmt_f(v.cy)}
                                r={fmt_f(if @visuals.height_size, do: v.radius, else: @detection_fixed_r)}
                                fill={v.color}
                                fill-opacity="0.5"
                                stroke={v.color}
                                stroke-width="1.5"
                              />
                            <% end %>
                            <%= if @visuals.labels and not v.merged? do %>
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

        <%= if @ui_mode == :developer do %>
        <div class="w-80 shrink-0 h-full overflow-y-auto flex flex-col gap-4 p-3 border-l border-base-300 bg-base-100">
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
                    <div class="flex flex-nowrap gap-1">
                      <%= for d <- @devices do %>
                        <button
                          type="button"
                          phx-click="toggle_sensor"
                          phx-value-device_id={d.device_id}
                          title={sensor_tooltip(d, @sensor_statuses[d.device_id])}
                          class={[
                            "btn btn-sm font-mono flex-1 min-w-0 px-1",
                            sensor_status_class(@sensor_statuses[d.device_id])
                          ]}
                        >
                          {device_letter(d.device_id)}
                        </button>
                      <% end %>
                    </div>
                  </div>

                  <div class="flex flex-col gap-1">
                    <label
                      id="radar-track-fusion"
                      class="flex items-center gap-2 cursor-pointer text-sm"
                    >
                      <input
                        type="checkbox"
                        class="checkbox checkbox-xs"
                        checked={@track_fusion}
                        phx-click="toggle_track_fusion"
                      />
                      <span>Fuse duplicate detections</span>
                    </label>
                    <p class="text-xs opacity-60">
                      Combines the same object seen by multiple sensors into one, so gravity/activity don't double up or flicker as it drifts between sensors' fields of view. Fused pairs are outlined in amber below.
                    </p>
                    <%= if @track_fusion do %>
                      <form
                        id="radar-track-fusion-radius-form"
                        phx-change="set_track_fusion_radius"
                        class="flex items-center gap-2 text-xs"
                      >
                        <label for="radar-track-fusion-radius" class="opacity-70">
                          Fusion radius
                        </label>
                        <input
                          id="radar-track-fusion-radius"
                          name="radius_m"
                          type="number"
                          min="0.1"
                          max="5"
                          step="0.1"
                          value={fmt_f(@track_fusion_radius_m)}
                          class="input input-bordered input-xs w-20 font-mono"
                        />
                        <span class="opacity-60">m</span>
                      </form>
                    <% end %>
                  </div>

                  <div class="flex flex-col gap-2 border-t border-base-300 pt-3">
                    <p class="text-xs font-semibold opacity-70">Panel gravity</p>

                    <%!-- Distance thresholds --%>
                    <form
                      id="radar-gravity-distances-form"
                      phx-change="set_gravity_distances"
                      class="grid grid-cols-2 gap-x-3 gap-y-1 items-end"
                    >
                      <div class="flex flex-col gap-1">
                        <label for="radar-gravity-near" class="text-xs opacity-70">Near (max %)</label>
                        <div class="flex items-center gap-1">
                          <input
                            id="radar-gravity-near"
                            name="near_dist_m"
                            type="number"
                            min="0.1"
                            max="10"
                            step="0.1"
                            value={fmt_f(@gravity_near_dist_m)}
                            phx-debounce="400"
                            class="input input-bordered input-xs w-16 font-mono"
                          />
                          <span class="text-xs opacity-60">m</span>
                        </div>
                      </div>
                      <div class="flex flex-col gap-1">
                        <label for="radar-gravity-far" class="text-xs opacity-70">Far (floor %)</label>
                        <div class="flex items-center gap-1">
                          <input
                            id="radar-gravity-far"
                            name="far_dist_m"
                            type="number"
                            min="0.2"
                            max="30"
                            step="0.1"
                            value={fmt_f(@gravity_far_dist_m)}
                            phx-debounce="400"
                            class="input input-bordered input-xs w-16 font-mono"
                          />
                          <span class="text-xs opacity-60">m</span>
                        </div>
                      </div>
                    </form>

                    <%!-- Brightness levels --%>
                    <form
                      id="radar-gravity-levels-form"
                      phx-change="set_gravity_levels"
                      class="flex flex-col gap-1"
                    >
                      <div class="flex flex-col gap-1">
                        <label for="radar-gravity-max" class="text-xs opacity-70">Max</label>
                        <div class="flex items-center gap-1">
                          <input
                            id="radar-gravity-max"
                            name="max_gravity_pct"
                            type="number"
                            min="0"
                            max="100"
                            step="1"
                            value={@gravity_max_pct}
                            phx-debounce="400"
                            class="input input-bordered input-xs w-16 font-mono"
                          />
                          <span class="text-xs opacity-60">%</span>
                        </div>
                      </div>
                    </form>

                    <label
                      id="radar-gravity-fuse"
                      class="flex items-center gap-2 cursor-pointer text-sm"
                    >
                      <input
                        type="checkbox"
                        class="checkbox checkbox-xs"
                        checked={@gravity_fuse}
                        phx-click="toggle_gravity_fuse"
                      />
                      <span>Fuse tracks</span>
                    </label>
                  </div>

                  <%= if mock_source?(@source_mode) do %>
                    <div class="flex flex-col gap-1">
                      <div class="flex items-center justify-between gap-2">
                        <label for="radar-manual" class="text-xs font-semibold opacity-70">
                          Cursor tracking
                        </label>
                        <input
                          id="radar-manual"
                          type="checkbox"
                          class="toggle toggle-sm toggle-primary"
                          checked={@manual_tracking}
                          phx-click="toggle_manual_tracking"
                        />
                      </div>
                      <p :if={@manual_tracking} class="text-xs opacity-60">
                        Move the cursor over the map to place the tracked object.
                      </p>
                    </div>

                    <%= unless @manual_tracking do %>
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
                  <% end %>

                  <%= if @source_mode == :live do %>
                    <div id="radar-sensitivity-control" class="flex flex-col gap-1">
                      <form
                        id="radar-sensitivity-form"
                        phx-change="set_sensitivity"
                        class="flex flex-col gap-1"
                      >
                        <label for="radar-sensitivity" class="text-xs font-semibold opacity-70">
                          Sensitivity
                        </label>
                        <div class="flex items-center gap-2">
                          <span class="text-xs opacity-60">lower</span>
                          <div
                            id="radar-sensitivity-input"
                            phx-hook=".RadarSensitivitySlider"
                            phx-update="ignore"
                            data-value={@sensitivity_level}
                            class="grow"
                          >
                            <input
                              id="radar-sensitivity"
                              name="sensitivity_level"
                              type="range"
                              min="1"
                              max="9"
                              step="1"
                              value={@sensitivity_level}
                              phx-debounce="300"
                              class="range range-sm w-full"
                            />
                            <script :type={Phoenix.LiveView.ColocatedHook} name=".RadarSensitivitySlider">
                              export default {
                                mounted() {
                                  this.range = this.el.querySelector('input[type="range"]')
                                },
                                updated() {
                                  this.range = this.el.querySelector('input[type="range"]')
                                  if (!this.range) return
                                  if (document.activeElement === this.range) return
                                  this.range.value = this.el.dataset.value
                                }
                              }
                            </script>
                          </div>
                          <span class="text-xs opacity-60">higher</span>
                        </div>
                      </form>
                      <span class="text-sm font-mono text-right">
                        {@sensitivity_level}/9 ({Octopus.Radar.SensorType.sensitivity_level_label(@sensitivity_level)})
                      </span>
                    </div>
                    <label
                      id="radar-clutter-filter"
                      class="flex items-center gap-2 cursor-pointer text-sm"
                    >
                      <input
                        type="checkbox"
                        class="checkbox checkbox-xs"
                        checked={@clutter_filter}
                        phx-click="toggle_clutter_filter"
                      />
                      <span>Hide static clutter</span>
                    </label>
                  <% end %>

                  <%= if @radial_layout do %>
                    <form
                      id="radar-sensor-rotation-form"
                      phx-change="set_sensor_rotation"
                      class="flex flex-col gap-1"
                    >
                      <label for="radar-rotation-target" class="text-xs font-semibold opacity-70">
                        Sensor rotation
                      </label>
                      <select
                        id="radar-rotation-target"
                        name="rotation_target"
                        class="select select-bordered w-full h-10 text-sm leading-normal font-mono"
                      >
                        <option value="global" selected={@rotation_target == "global"}>
                          Alle Sensoren
                        </option>
                        <%= for d <- @layout_devices do %>
                          <option
                            value={Integer.to_string(d.device_id)}
                            selected={@rotation_target == Integer.to_string(d.device_id)}
                          >
                            Sensor {device_letter(d.device_id)}{sensor_rotation_modified_marker(d.device_id, @sensor_installation_angles)}
                          </option>
                        <% end %>
                      </select>
                      <input type="hidden" name="rotation_seq" value="0" />
                      <div
                        id="radar-sensor-rotation-input"
                        phx-hook=".RadarRotationSlider"
                        data-value={rotation_slider_value(@rotation_target, @angle_offset_deg, @sensor_installation_angles)}
                      >
                        <input
                          id="radar-sensor-rotation"
                          name="rotation_deg"
                          type="range"
                          min="0"
                          max="359"
                          step="1"
                          value={rotation_slider_value(@rotation_target, @angle_offset_deg, @sensor_installation_angles)}
                          class="range range-sm w-full"
                        />
                        <script :type={Phoenix.LiveView.ColocatedHook} name=".RadarRotationSlider">
                          export default {
                            mounted() {
                              this.range = this.el.querySelector('input[type="range"]')
                              this.seqInput = this.el.closest('form')?.querySelector('input[name="rotation_seq"]')
                              this.label = this.el.closest('form')?.querySelector('[data-rotation-label]')

                              this.syncSlider = (value) => {
                                if (!this.range || document.activeElement === this.range) return
                                if (value == null) return
                                this.range.value = String(value)
                              }

                              this.handleEvent("sync_rotation_slider", ({ value }) => {
                                this.syncSlider(value)
                              })

                              this.updateLabel = () => {
                                if (this.label && this.range) {
                                  this.label.textContent = `${this.range.value}°`
                                }
                              }

                              this.onInput = () => {
                                if (this.seqInput) {
                                  this.seqInput.value = String(Number(this.seqInput.value || 0) + 1)
                                }
                                this.updateLabel()
                              }

                              this.onRelease = () => {
                                if (this.seqInput) {
                                  this.seqInput.value = String(Number(this.seqInput.value || 0) + 1)
                                }
                                this.el.closest('form')?.requestSubmit()
                              }

                              this.range?.addEventListener("input", this.onInput, { capture: true })
                              this.range?.addEventListener("change", this.onRelease)
                            },
                            destroyed() {
                              this.range?.removeEventListener("input", this.onInput, { capture: true })
                              this.range?.removeEventListener("change", this.onRelease)
                            },
                            updated() {
                              this.range = this.el.querySelector('input[type="range"]')
                              this.syncSlider(this.el.dataset.value)
                            }
                          }
                        </script>
                      </div>
                      <span data-rotation-label class="text-sm font-mono text-right">
                        {rotation_slider_value(@rotation_target, @angle_offset_deg, @sensor_installation_angles)}°
                      </span>
                    </form>
                  <% end %>

                  <button
                    id="radar-reinit"
                    type="button"
                    class="btn btn-outline btn-sm w-full"
                    phx-click="reinitialize"
                  >
                    Reinitialize all sensors
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
        <% end %>
      </div>
    <% end %>
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
      max_y: max_y
    } = assigns

    now = System.monotonic_time(:millisecond)
    trail_cutoff = now - @trail_ms

    samples_by_key = group_samples_by_key(samples, trail_cutoff)
    fusion_clusters = build_fusion_clusters(tracks_now)

    Enum.map(tracks_now, fn {{device_id, id} = key, t} ->
      cx = world_to_svg_x(t.x, min_x, max_x)
      cy = world_to_svg_y(t.y, min_y, max_y)
      age = now - t.last_seen
      opacity = max(0.0, 1.0 - age / @fade_ms)

      arrow_dx = clamp(t.vx * @velocity_scale, -@velocity_max_len, @velocity_max_len)
      arrow_dy = clamp(t.vy * @velocity_scale, -@velocity_max_len, @velocity_max_len)

      hue = sensor_hue(device_id)
      speed = :math.sqrt(t.vx * t.vx + t.vy * t.vy)

      trail_segments =
        samples_by_key
        |> Map.get(key, [])
        |> build_trail_segments(now, hue, min_x, max_x, min_y, max_y)

      cluster = Map.get(fusion_clusters, key)

      %{
        device_id: device_id,
        track_id: id,
        label: track_label(device_id, id),
        cx: cx,
        cy: cy,
        radius: radius_for_z(t.z),
        opacity: opacity,
        color: sensor_color(device_id),
        arrow_x: cx + arrow_dx,
        arrow_y: cy - arrow_dy,
        trail: trail_segments,
        merged?: cluster != nil,
        cluster_id: cluster && cluster.cluster_id,
        sensor_ids: (cluster && cluster.sensor_ids) || [],
        speed: speed,
        vx: t.vx,
        vy: t.vy,
        z: t.z,
        stale_ms: age,
        track_alive_ms: now - t.first_seen
      }
    end)
  end

  # Maps every `{device_id, track_id}` that took part in an actual cross-sensor
  # fusion to its cluster index and the (sorted, de-duplicated) sensor ids that
  # contributed to it, so the view can highlight fused detections, draw a link
  # between them, and render the per-sensor pie breakdown. Empty (no
  # highlight) when fusion is off or there is nothing to merge — this mirrors
  # exactly what `Radar.fuse_people/1` will hand to PanelGravity/PanelActivity,
  # not a separate preview computation.
  defp build_fusion_clusters(tracks_now) do
    if Radar.track_fusion_enabled?() do
      tracks_now
      |> Enum.map(fn {{device_id, id} = key, t} ->
        %{id: TrackMerge.encode_id(device_id, id), key: key, x: t.x, y: t.y, vx: t.vx, vy: t.vy}
      end)
      |> Radar.fuse_groups()
      |> Enum.filter(& &1.merged?)
      |> Enum.with_index()
      |> Enum.flat_map(fn {%{sources: sources}, cluster_id} ->
        sensor_ids = sources |> Enum.map(&TrackMerge.device_id/1) |> Enum.uniq() |> Enum.sort()

        Enum.map(sources, fn source ->
          {source.key, %{cluster_id: cluster_id, sensor_ids: sensor_ids}}
        end)
      end)
      |> Map.new()
    else
      %{}
    end
  end

  # One line per pair in a fused cluster (a star from the first member when
  # more than two sensors detect the same object, which is rare).
  defp build_fusion_links(view_targets) do
    view_targets
    |> Enum.filter(& &1.merged?)
    |> Enum.group_by(& &1.cluster_id)
    |> Enum.flat_map(fn {_cluster_id, members} -> fusion_link_segments(members) end)
  end

  defp fusion_link_segments([_single]), do: []
  defp fusion_link_segments([a, b]), do: [%{x1: a.cx, y1: a.cy, x2: b.cx, y2: b.cy}]

  defp fusion_link_segments([anchor | rest]) do
    Enum.map(rest, fn m -> %{x1: anchor.cx, y1: anchor.cy, x2: m.cx, y2: m.cy} end)
  end

  # Every label is prefixed by the source sensor's letter so two sensors
  # reporting the same numeric id are distinguishable.
  defp track_label(device_id, id), do: "#{device_letter(device_id)}#{id}"

  defp build_detection_list(tracks_now, devices, mode) do
    tracks_now
    |> tracks_to_list(devices)
    |> case do
      [] -> []
      tracks -> apply_detection_list_mode(tracks, devices, mode)
    end
  end

  defp tracks_to_list(tracks_now, devices) do
    now = System.monotonic_time(:millisecond)
    poses = sensor_pose_lookup(devices)

    Enum.map(tracks_now, fn {{device_id, id}, t} ->
      vz = Map.get(t, :vz, 0.0)
      speed = :math.sqrt(t.vx * t.vx + t.vy * t.vy + vz * vz)
      age = now - t.last_seen
      opacity = max(0.0, 1.0 - age / @fade_ms)
      {lx, ly, lz} = local_coords(t, Map.get(poses, device_id))

      %{
        device_id: device_id,
        id: id,
        label: track_label(device_id, id),
        x: t.x,
        y: t.y,
        z: t.z,
        lx: lx,
        ly: ly,
        lz: lz,
        speed: speed,
        opacity: opacity,
        color: sensor_color(device_id),
        letter: device_letter(device_id)
      }
    end)
  end

  # device_id → pose keyword usable by `Transform`, so a global track can be
  # inverted back to the raw coordinates the sensor originally reported.
  defp sensor_pose_lookup(devices) do
    Map.new(devices, fn d ->
      {d.device_id,
       [
         type: d.type,
         angle_deg: d.angle_deg,
         distance_cm: d.distance_cm,
         rotation_deg: d.rotation_deg
       ]}
    end)
  end

  # Recover the sensor-local (raw) coordinates by inverting the forward
  # Transform. Falls back to the global values if the pose is unknown.
  defp local_coords(t, nil), do: {t.x, t.y, t.z}

  defp local_coords(t, pose) do
    local =
      Transform.global_to_local_track(
        %Track{id: 0, reserved: 0, x: t.x, y: t.y, z: t.z, vx: 0.0, vy: 0.0, vz: 0.0},
        pose
      )

    {local.x, local.y, local.z}
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

  # Inverse of world_to_svg_x/y: viewBox coordinates (0..@vb) back to world
  # meters. Y is flipped because SVG y grows downward while world y grows up.
  defp svg_to_world(vbx, vby, min_x, max_x, min_y, max_y) do
    x = min_x + vbx / @vb * (max_x - min_x)
    y = min_y + (@vb - vby) / @vb * (max_y - min_y)
    {x, y}
  end

  defp to_f(v) when is_number(v), do: v * 1.0

  defp to_f(v) when is_binary(v) do
    case Float.parse(v) do
      {f, _} -> f
      :error -> 0.0
    end
  end

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

  # Splits a combined-object marker into equal pie slices, one per
  # contributing sensor, so a fused detection visually shows *which* sensors
  # agreed on it instead of just a single flat color.
  defp pie_slices(_cx, _cy, _r, []), do: []

  defp pie_slices(cx, cy, r, [device_id]),
    do: [%{d: full_circle_path(cx, cy, r), color: sensor_color(device_id)}]

  defp pie_slices(cx, cy, r, sensor_ids) do
    step = 360.0 / length(sensor_ids)

    sensor_ids
    |> Enum.with_index()
    |> Enum.map(fn {device_id, i} ->
      %{
        d: pie_slice_path(cx, cy, r, i * step, (i + 1) * step),
        color: sensor_color(device_id)
      }
    end)
  end

  defp pie_slice_path(cx, cy, r, start_deg, end_deg) do
    {x1, y1} = point_on_circle(cx, cy, r, start_deg)
    {x2, y2} = point_on_circle(cx, cy, r, end_deg)
    large_arc = if end_deg - start_deg > 180.0, do: 1, else: 0

    "M #{fmt_f(cx)},#{fmt_f(cy)} L #{fmt_f(x1)},#{fmt_f(y1)} A #{fmt_f(r)},#{fmt_f(r)} 0 #{large_arc} 1 #{fmt_f(x2)},#{fmt_f(y2)} Z"
  end

  defp full_circle_path(cx, cy, r) do
    {x1, y1} = point_on_circle(cx, cy, r, 0.0)
    {x2, y2} = point_on_circle(cx, cy, r, 180.0)

    "M #{fmt_f(x1)},#{fmt_f(y1)} A #{fmt_f(r)},#{fmt_f(r)} 0 1 1 #{fmt_f(x2)},#{fmt_f(y2)} " <>
      "A #{fmt_f(r)},#{fmt_f(r)} 0 1 1 #{fmt_f(x1)},#{fmt_f(y1)} Z"
  end

  defp point_on_circle(cx, cy, r, angle_deg) do
    theta = angle_deg * :math.pi() / 180.0
    {cx + r * :math.sin(theta), cy - r * :math.cos(theta)}
  end

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

  defp rotation_deg_changed?(%{"_target" => ["rotation_deg"]}), do: true
  defp rotation_deg_changed?(%{"rotation_deg" => v}) when is_binary(v) and v != "", do: true
  defp rotation_deg_changed?(_), do: false

  defp maybe_push_rotation_slider_sync(socket, params) do
    if rotation_target_changed?(params) do
      push_event(socket, "sync_rotation_slider", %{
        "value" =>
          rotation_slider_value(
            socket.assigns.rotation_target,
            socket.assigns.angle_offset_deg,
            socket.assigns.sensor_installation_angles
          )
      })
    else
      socket
    end
  end

  defp rotation_target_changed?(%{"_target" => ["rotation_target"]}), do: true
  defp rotation_target_changed?(_), do: false

  defp apply_rotation_deg(socket, target, v) do
    case parse_degree(v) do
      {:ok, deg} ->
        case parse_rotation_target(target) do
          :global ->
            Radar.set_angle_offset_deg(deg)
            assign(socket, :angle_offset_deg, round(deg))

          {:sensor, device_id} ->
            Radar.set_sensor_installation_angle_deg(device_id, deg)

            assign(
              socket,
              :sensor_installation_angles,
              Map.put(socket.assigns.sensor_installation_angles, device_id, deg * 1.0)
            )
        end

      :error ->
        socket
    end
  end

  defp rotation_slider_value("global", angle_offset_deg, _angles), do: round(angle_offset_deg)

  defp rotation_slider_value(target, _angle_offset_deg, angles) when is_binary(target) do
    case parse_rotation_target(target) do
      {:sensor, device_id} -> angles |> Map.get(device_id, 0.0) |> round()
      :global -> 0
    end
  end

  defp sensor_rotation_modified_marker(device_id, angles) do
    if sensor_rotation_modified?(device_id, angles), do: " ·", else: ""
  end

  defp sensor_rotation_modified?(device_id, angles) do
    angles |> Map.get(device_id, 0.0) |> round() != 0
  end

  defp normalize_rotation_target("global"), do: "global"

  defp normalize_rotation_target(target) when is_binary(target), do: target

  defp normalize_rotation_target(target) when is_integer(target), do: Integer.to_string(target)

  defp normalize_rotation_target(_), do: "global"

  defp parse_rotation_target("global"), do: :global

  defp parse_rotation_target(target) when is_binary(target) do
    case Integer.parse(target) do
      {device_id, _} when device_id > 0 -> {:sensor, device_id}
      _ -> :global
    end
  end

  defp parse_rotation_seq(v) when is_binary(v) do
    case Integer.parse(v) do
      {seq, _} when seq >= 0 -> {:ok, seq}
      _ -> :error
    end
  end

  defp parse_rotation_seq(_), do: :error

  defp parse_degree(v) when is_binary(v) do
    case Float.parse(v) do
      {deg, _} -> {:ok, deg}
      :error -> :error
    end
  end

  defp parse_float(v, default) when is_binary(v) do
    case Float.parse(v) do
      {f, _} -> f
      :error -> default
    end
  end

  defp parse_float(v, _default) when is_number(v), do: v * 1.0
  defp parse_float(_, default), do: default

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
        "Sensitivity: #{d.sensitivity_level}/9 (#{Octopus.Radar.SensorType.sensitivity_level_label(d.sensitivity_level)})",
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

  ## Detection dump (coordinate debugging)

  defp dump_track_history(device_id, track_id) do
    label = track_label(device_id, track_id)

    case Radar.clutter_filter_track_debug(device_id, track_id) do
      nil ->
        Logger.info(
          "RADAR-TRACK-HISTORY-DUMP[#{label}] track not found in clutter-filter registry (device_id=#{device_id}, track_id=#{track_id})"
        )

      payload ->
        dump_id = track_history_dump_id(label)
        json = Jason.encode!(Map.put(payload, "dump_id", dump_id))
        Logger.info("RADAR-TRACK-HISTORY-DUMP[#{dump_id}] #{json}")
    end
  end

  defp track_history_dump_id(label) do
    ts = Calendar.strftime(DateTime.utc_now(), "%Y%m%dT%H%M%SZ")
    "history-#{label}-#{ts}"
  end

  defp dump_detections_id do
    Calendar.strftime(DateTime.utc_now(), "detections-%Y%m%dT%H%M%SZ")
  end

  defp generate_detections_dump_json(assigns, dump_id) do
    payload = %{
      "captured_at" => DateTime.to_iso8601(DateTime.utc_now()),
      "dump_id" => dump_id,
      "layout" => detection_dump_layout(assigns),
      "sensors" => detection_dump_sensors(assigns.layout_devices),
      "detections" => detection_dump_entries(assigns.tracks_now, assigns.devices)
    }

    payload =
      if mock_source?(assigns.source_mode) and assigns.world_objects != [] do
        Map.put(payload, "ground_truth", Enum.map(assigns.world_objects, &ground_truth_dump_entry/1))
      else
        payload
      end

    Jason.encode!(payload)
  end

  defp detection_dump_layout(assigns) do
    %{
      "source_mode" => Atom.to_string(assigns.source_mode),
      "layout_start_angle_deg" => round(Radar.layout_start_angle_deg()),
      "angle_offset_deg" => assigns.angle_offset_deg,
      "sensor_installation_angles" => assigns.sensor_installation_angles,
      "north_panel" => assigns.north_panel,
      "radial_layout" => assigns.radial_layout
    }
  end

  defp detection_dump_sensors(layout_devices) do
    Enum.map(layout_devices, fn d ->
      {tx, ty} = sensor_position(d)

      %{
        "device_id" => d.device_id,
        "letter" => device_letter(d.device_id),
        "active" => Radar.sensor_active?(d.device_id),
        "type" => Atom.to_string(d.type),
        "angle_deg" => d.angle_deg,
        "distance_cm" => d.distance_cm,
        "rotation_deg" => d.rotation_deg,
        "mount_x_m" => fmt_json_float(tx),
        "mount_y_m" => fmt_json_float(ty)
      }
    end)
  end

  defp detection_dump_entries(tracks_now, devices) do
    now = System.monotonic_time(:millisecond)
    poses = sensor_pose_lookup(devices)

    tracks_now
    |> Enum.map(fn {{device_id, id}, t} ->
      {lx, ly, lz} = local_coords(t, Map.get(poses, device_id))
      vz = Map.get(t, :vz, 0.0)
      speed = :math.sqrt(t.vx * t.vx + t.vy * t.vy + vz * vz)

      %{
        "device_id" => device_id,
        "letter" => device_letter(device_id),
        "track_id" => id,
        "label" => track_label(device_id, id),
        "global" => coords_map(t.x, t.y, t.z),
        "local" => coords_map(lx, ly, lz),
        "velocity" => coords_map(t.vx, t.vy, vz),
        "speed_m_s" => fmt_json_float(speed),
        "last_seen_ms_ago" => now - t.last_seen,
        "first_seen_ms_ago" => now - t.first_seen,
        "stationary_ms" => now - t.position_last_changed
      }
    end)
    |> Enum.sort_by(&{&1["device_id"], &1["track_id"]})
  end

  defp ground_truth_dump_entry(o) do
    %{
      "id" => o.id,
      "x_m" => fmt_json_float(o.x),
      "y_m" => fmt_json_float(o.y),
      "z_m" => fmt_json_float(o.z)
    }
  end

  defp coords_map(x, y, z) do
    %{"x_m" => fmt_json_float(x), "y_m" => fmt_json_float(y), "z_m" => fmt_json_float(z)}
  end

  defp fmt_json_float(v) when is_float(v), do: Float.round(v, 4)
  defp fmt_json_float(v) when is_integer(v), do: v * 1.0

  defp track_position_moved?(prev, %Track{} = t) do
    dx = t.x - prev.x
    dy = t.y - prev.y
    dz = t.z - prev.z

    :math.sqrt(dx * dx + dy * dy + dz * dz) > @position_stationary_threshold_m
  end

  ## Formatting helpers

  defp fmt_f(v) when is_integer(v), do: Integer.to_string(v)
  defp fmt_f(v) when is_float(v), do: :erlang.float_to_binary(v, decimals: 2)

  defp detection_tooltip(v) do
    f2 = fn x -> :erlang.float_to_binary(x * 1.0, decimals: 2) end

    stale_line =
      if v.stale_ms > 50,
        do: "\nStale: #{f2.(v.stale_ms / 1000.0)} s",
        else: ""

    "Track #{v.label}\n" <>
      "Speed: #{f2.(v.speed)} m/s  vx=#{f2.(v.vx)}  vy=#{f2.(v.vy)}\n" <>
      "Height: #{f2.(v.z)} m\n" <>
      "Active: #{f2.(v.track_alive_ms / 1000.0)} s" <>
      stale_line
  end

  defp fmt_m(v) when is_integer(v), do: Integer.to_string(v) <> " m"
  defp fmt_m(v) when is_float(v), do: :erlang.float_to_binary(v, decimals: 2) <> " m"
end
