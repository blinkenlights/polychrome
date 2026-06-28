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

  # Padding (in meters) added around the data to avoid divide-by-zero
  # when the window is empty or all samples coincide.
  @minmax_pad_m 0.5

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
    devices = Radar.devices() |> Enum.filter(& &1.enabled)
    mock_mode = Radar.mock_mode()
    world_radius = Radar.world_radius_m()
    platform_radius = Octopus.Params.Sim3d.platform_radius_m()

    if connected?(socket) and Radar.enabled?() do
      Radar.subscribe()
      Enum.each(devices, &Radar.subscribe_status(&1.device_id))
      if mock_mode != :off, do: subscribe_world()
      # Track the Sim3D platform radius so the drawn chill zone matches the mock.
      Phoenix.PubSub.subscribe(Octopus.PubSub, Octopus.Params.Sim3d.topic())
      Process.send_after(self(), :refresh_sensor_statuses, 2_000)
    end

    selected_id =
      cond do
        mock_mode != :off -> :all
        length(devices) == 1 -> hd(devices).device_id
        true -> :all
      end

    selected = Enum.find(devices, &(&1.device_id == selected_id))

    {:ok,
     socket
     |> assign(:radar_enabled, Radar.enabled?())
     |> assign(:devices, devices)
     |> assign(:sensor_statuses, build_sensor_statuses(devices))
     |> assign(:selected_device_id, selected_id)
     |> assign(:sensitivity, (selected && selected.sensitivity) || 4)
     |> assign(:mock_mode, mock_mode)
     |> assign(:max_people, safe_max_people())
     |> assign(:max_people_limit, Radar.max_people_limit())
     |> assign(:max_people_applying, false)
     |> assign(:max_people_applying_until, 0)
     |> assign(:entropy, safe_entropy())
     |> assign(:world_radius, world_radius)
     |> assign(:platform_radius, platform_radius)
     |> assign(:world_objects, [])
     |> assign(:visuals, @default_visuals)
     |> assign(:bounds_mode, :static)
     |> assign(:static_bounds, bounds_for(mock_mode, selected_id, devices, world_radius))
     |> reset_radar_state()}
  end

  # The canvas always frames the entire simulated world (in every mode) so the
  # world border, the sensors and their coverage, and the detections all share
  # one fixed, fully-visible frame. The extent is padded slightly past the
  # world radius so the border circle isn't clipped at the canvas edge.
  defp bounds_for(_mode, _selected_id, _devices, radius), do: world_bounds(radius)

  defp world_bounds(radius) do
    ext = radius * 1.08
    %{min_x: -ext, max_x: ext, min_y: -ext, max_y: ext, range_m: radius}
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

  def handle_event("set_mock_mode", %{"mode" => mode_str}, socket) do
    # The mode change is broadcast on the radar topic; this LiveView (and any
    # others) updates itself in handle_info({:mock_mode_changed, _}, …).
    Radar.set_mock_mode(parse_mode(mode_str))
    {:noreply, socket}
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

  def handle_info({:mock_mode_changed, mode}, socket) do
    if connected?(socket) do
      if mode == :off, do: unsubscribe_world(), else: subscribe_world()
    end

    {:noreply,
     socket
     |> assign(:mock_mode, mode)
     |> assign(:max_people, safe_max_people())
     |> assign(:max_people_applying, false)
     |> assign(:entropy, safe_entropy())
     |> assign(:selected_device_id, :all)
     |> assign(:bounds_mode, :static)
     |> assign(:world_objects, [])
     |> assign(:static_bounds, bounds_for(mode, :all, socket.assigns.devices, socket.assigns.world_radius))
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
    selected = socket.assigns.selected_device_id

    if selected == :all or selected == device_id do
      {:noreply, ingest_frame(socket, device_id, frame)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:platform_radius_m, value}, socket) do
    {:noreply, socket |> assign(:platform_radius, value) |> rebuild_view()}
  end

  # The Sim3D topic carries other parameter broadcasts too; ignore them.
  def handle_info(_msg, socket), do: {:noreply, socket}

  ## State updates

  defp reset_radar_state(socket) do
    socket
    |> assign(:samples, [])
    |> assign(:tracks_now, %{})
    |> assign(:last_frame_number, nil)
    |> assign(:min_z, nil)
    |> assign(:max_z, nil)
    |> assign(:view_targets, [])
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
  defp active_bounds(socket, selected_id) do
    bounds_for(socket.assigns.mock_mode, selected_id, socket.assigns.devices, socket.assigns.world_radius)
  end

  defp empty_ruler,
    do: %{x_axis_visible: false, y_axis_visible: false, origin_x: 0, origin_y: 0, ticks: []}

  defp ingest_frame(socket, device_id, %Frame{tracks: tracks, frame_number: frame_number}) do
    now = System.monotonic_time(:millisecond)
    cutoff = now - @window_ms
    fade_cutoff = now - @fade_ms

    new_samples =
      Enum.map(tracks, fn %Track{id: id, x: x, y: y, z: z} ->
        %{ts: now, device_id: device_id, id: id, x: x, y: y, z: z}
      end)

    samples =
      (new_samples ++ socket.assigns.samples)
      |> Enum.filter(&(&1.ts >= cutoff))

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
          last_seen: now
        })
      end)
      |> Enum.reject(fn {_key, t} -> t.last_seen < fade_cutoff end)
      |> Map.new()

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

    range_indicators =
      build_range_indicators(a.devices, a.selected_device_id, min_x, max_x, min_y, max_y)

    world_sensors = build_world_sensors(a.devices, min_x, max_x, min_y, max_y)

    # The world border frames every mode; ground-truth people only exist in
    # mock mode.
    world_border = build_world_border(a.world_radius, min_x, max_x, min_y, max_y)
    platform_ring = build_platform_ring(a.platform_radius, min_x, max_x, min_y, max_y)

    ground_truth =
      if a.mock_mode == :off,
        do: [],
        else: build_ground_truth(a.world_objects, min_x, max_x, min_y, max_y)

    socket
    |> assign(:view_targets, view_targets)
    |> assign(:ruler, ruler)
    |> assign(:range_indicators, range_indicators)
    |> assign(:world_sensors, world_sensors)
    |> assign(:ground_truth, ground_truth)
    |> assign(:world_border, world_border)
    |> assign(:platform_ring, platform_ring)
  end

  # One coverage ellipse per sensor in the current selection, centered on the
  # sensor's global mount position and tinted in that sensor's color.
  defp build_range_indicators(_devices, nil, _, _, _, _), do: []

  defp build_range_indicators(devices, :all, min_x, max_x, min_y, max_y) do
    Enum.map(devices, &range_indicator(&1, min_x, max_x, min_y, max_y))
  end

  defp build_range_indicators(devices, device_id, min_x, max_x, min_y, max_y)
       when is_integer(device_id) do
    case Enum.find(devices, &(&1.device_id == device_id)) do
      nil -> []
      device -> [range_indicator(device, min_x, max_x, min_y, max_y)]
    end
  end

  defp range_indicator(device, min_x, max_x, min_y, max_y) do
    range_m = device.range_cm / 100.0
    {tx, ty} = sensor_position(device)

    %{
      id: device.device_id,
      cx: scale(tx, min_x, max_x, @vb),
      cy: scale(ty, min_y, max_y, @vb),
      rx: range_m / (max_x - min_x) * @vb,
      ry: range_m / (max_y - min_y) * @vb,
      color: sensor_color(device.device_id)
    }
  end

  # Sensor placement markers (square + label) in the global frame.
  defp build_world_sensors(devices, min_x, max_x, min_y, max_y) do
    Enum.map(devices, fn device ->
      {tx, ty} = sensor_position(device)

      %{
        cx: scale(tx, min_x, max_x, @vb),
        cy: scale(ty, min_y, max_y, @vb),
        half: @sensor_marker_half,
        label: device_letter(device.device_id),
        color: sensor_color(device.device_id)
      }
    end)
  end

  # Ground-truth people as small black dots.
  defp build_ground_truth(objects, min_x, max_x, min_y, max_y) do
    Enum.map(objects, fn o ->
      %{
        id: o.id,
        cx: scale(o.x, min_x, max_x, @vb),
        cy: scale(o.y, min_y, max_y, @vb),
        r: @ground_truth_r
      }
    end)
  end

  # The outer edge of the simulated world (a circle of radius `radius_m`
  # centered on the origin), as an ellipse to honor non-uniform axis scales.
  defp build_world_border(radius_m, min_x, max_x, min_y, max_y) do
    %{
      cx: scale(0.0, min_x, max_x, @vb),
      cy: scale(0.0, min_y, max_y, @vb),
      rx: radius_m / (max_x - min_x) * @vb,
      ry: radius_m / (max_y - min_y) * @vb
    }
  end

  # The central platform ("chill zone", radius `platform_radius_m`), drawn the
  # same way as the world border so it honors non-uniform axis scales.
  defp build_platform_ring(nil, _min_x, _max_x, _min_y, _max_y), do: nil

  defp build_platform_ring(radius_m, min_x, max_x, min_y, max_y) do
    %{
      cx: scale(0.0, min_x, max_x, @vb),
      cy: scale(0.0, min_y, max_y, @vb),
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
        <div class="card-body">
          <div class="flex items-center justify-between flex-wrap gap-4">
            <h1 class="card-title text-2xl">Radar</h1>
            <%= cond do %>
              <% not @radar_enabled -> %>
                <span class="text-sm opacity-70">
                  Radar disabled in config (<code>enabled: false</code> or <code>RADAR_ENABLED</code>)
                </span>
              <% @devices == [] -> %>
                <span class="text-sm opacity-70">No radar sensors configured</span>
              <% true -> %>
                <div class="flex items-center gap-3 flex-wrap">
                  <%!-- Data source: real hardware ("Live") vs the simulated world --%>
                  <div class="flex items-center gap-2">
                    <span class="text-sm opacity-70">Source</span>
                    <div class="join" id="radar-mock-mode">
                      <%= for {value, label} <- [{"off", "Live"}, {"exact", "Mock · Exact"}, {"fuzzy", "Mock · Fuzzy"}] do %>
                        <button
                          type="button"
                          phx-click="set_mock_mode"
                          phx-value-mode={value}
                          class={[
                            "btn btn-sm join-item",
                            if(Atom.to_string(@mock_mode) == value, do: "btn-primary", else: "btn-outline")
                          ]}
                        >
                          {label}
                        </button>
                      <% end %>
                    </div>
                  </div>
                  <%!-- Status / active-inactive buttons — one per config-enabled sensor --%>
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
                  <%!-- Sensor selector dropdown --%>
                  <form phx-change="select_sensor">
                    <select id="radar-sensor" name="device_id" class="select select-bordered min-w-40">
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
            <% end %>
          </div>

          <%= if @radar_enabled and @devices != [] do %>
            <div class="flex items-center flex-wrap gap-4 mt-2">
              <%= if @mock_mode != :off do %>
                <form phx-change="set_max_people" class="flex items-center gap-2">
                  <label for="radar-max-people" class="text-sm whitespace-nowrap">
                    Max people
                  </label>
                  <div class="join">
                    <input
                      id="radar-max-people"
                      name="max_people"
                      type="number"
                      inputmode="numeric"
                      min="1"
                      max={@max_people_limit}
                      value={@max_people}
                      phx-debounce="400"
                      class="input input-bordered input-sm join-item w-20 font-mono text-right"
                    />
                    <span class="join-item btn btn-sm btn-disabled font-mono pointer-events-none">
                      / {@max_people_limit}
                    </span>
                  </div>
                  <span
                    :if={@max_people_applying}
                    class="flex items-center gap-1 text-xs opacity-70 whitespace-nowrap"
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
                <form phx-change="set_entropy" class="flex items-center gap-3 grow min-w-0">
                  <label for="radar-entropy" class="text-sm whitespace-nowrap">
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
                    class="range range-sm grow"
                  />
                  <span class="text-sm font-mono w-12 text-right">{@entropy}%</span>
                </form>
              <% end %>
              <%= if @mock_mode == :off do %>
                <form phx-change="set_sensitivity" class="flex items-center gap-3 grow min-w-0">
                  <label for="radar-sensitivity" class="text-sm whitespace-nowrap">
                    Sensitivity
                  </label>
                  <span class="text-xs opacity-60 whitespace-nowrap">lower</span>
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
                  <span class="text-xs opacity-60 whitespace-nowrap">higher</span>
                </form>
              <% end %>
              <button
                id="radar-reinit"
                type="button"
                class="btn btn-outline btn-sm"
                phx-click="reinitialize"
              >
                <%= if @selected_device_id == :all do %>
                  Reinitialize all sensors
                <% else %>
                  Reinitialize sensor
                <% end %>
              </button>
            </div>
          <% end %>

          <%= if not @radar_enabled do %>
            <div class="alert alert-info mt-4">
              <span>
                Enable radar in <code>config/radar.exs</code> (<code>enabled: true</code>) or set
                <code>RADAR_ENABLED=true</code>, then restart the application.
              </span>
            </div>
          <% else %>
            <%= if @devices == [] do %>
              <div class="alert alert-info mt-4">
                <span>
                  Add at least one sensor under <code>:sensors</code> in
                  <code>config/radar.exs</code> or <code>config/radar.local.exs</code>.
                </span>
              </div>
            <% else %>
              <div class="flex gap-4 mt-4 items-start flex-wrap md:flex-nowrap">
                <%!-- Unified top-down display, always square and capped to the viewport. --%>
                <div class="flex-1 min-w-0 flex justify-center">
                  <div
                    class="aspect-square bg-base-200 rounded w-full"
                    style="max-height: min(80vh, 100%); max-width: min(80vh, 100%);"
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

                      <%!-- Sensor coverage: radial fill fading with distance (signal
                           strength) plus a 50% gray border marking the range edge. --%>
                      <%= if @visuals.coverage do %>
                        <defs>
                          <%= for r <- @range_indicators do %>
                            <radialGradient id={"rangegrad-#{r.id}"}>
                              <stop offset="0%" stop-color={r.color} stop-opacity="0.5" />
                              <stop offset="65%" stop-color={r.color} stop-opacity="0.18" />
                              <stop offset="100%" stop-color={r.color} stop-opacity="0" />
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
                            stroke="#808080"
                            stroke-opacity="0.5"
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
                          <rect
                            x={fmt_f(s.cx - s.half)}
                            y={fmt_f(s.cy - s.half)}
                            width={fmt_f(s.half * 2)}
                            height={fmt_f(s.half * 2)}
                            rx="3"
                            fill={s.color}
                            fill-opacity="0.35"
                            stroke={s.color}
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

                <%!-- Feature legend / toggles --%>
                <div class="w-48 shrink-0 flex flex-col gap-2">
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
      cx = scale(t.x, min_x, max_x, @vb)
      cy = scale(t.y, min_y, max_y, @vb)
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
        arrow_y: cy + arrow_dy,
        trail: trail_segments
      }
    end)
  end

  # In :all mode every label is prefixed by the source sensor's letter so two
  # sensors reporting the same numeric id are distinguishable.
  defp track_label(device_id, id, :all), do: "#{device_letter(device_id)}#{id}"
  defp track_label(_device_id, id, _selected), do: Integer.to_string(id)

  defp build_trail_segments(samples, now, hue, min_x, max_x, min_y, max_y) do
    samples
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [s1, s2] ->
      %{
        x1: scale(s1.x, min_x, max_x, @vb),
        y1: scale(s1.y, min_y, max_y, @vb),
        x2: scale(s2.x, min_x, max_x, @vb),
        y2: scale(s2.y, min_y, max_y, @vb),
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
    origin_x = scale(0.0, min_x, max_x, @vb)
    origin_y = scale(0.0, min_y, max_y, @vb)

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
        pos = scale(dm / 10, lo_w, hi_w, @vb)

        case orientation do
          :horizontal ->
            %{x1: pos, y1: axis_pos - half, x2: pos, y2: axis_pos + half, major?: major?}

          :vertical ->
            %{x1: axis_pos - half, y1: pos, x2: axis_pos + half, y2: pos, major?: major?}
        end
      end)
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

  defp trail_color(hue, age_ms) do
    age_fraction = min(1.0, age_ms / @trail_ms)
    lightness = @trail_l_near + age_fraction * (@trail_l_far - @trail_l_near)
    "hsl(#{hue}, #{@body_saturation}%, #{round(lightness)}%)"
  end

  ## Mock mode helpers

  defp parse_mode("exact"), do: :exact
  defp parse_mode("fuzzy"), do: :fuzzy
  defp parse_mode(_), do: :off

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
end
