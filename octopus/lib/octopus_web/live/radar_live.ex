defmodule OctopusWeb.RadarLive do
  @moduledoc """
  Live visualization of one HLK-LD6001A-60G radar's tracked targets.

  Subscribes to the global radar topic and renders the currently selected
  sensor's tracks as an inline SVG with auto-scaled axes (10 s rolling
  min/max), per-target colors, height-encoded radius, velocity arrows, ID
  labels, position trails and fade-out for stale tracks. All state and
  rendering live on the server; LiveView's diffing pushes the per-frame
  attribute updates over WebSocket.
  """

  use OctopusWeb, :live_view

  alias Octopus.Radar
  alias Octopus.Radar.{Frame, Track}

  # 10 s rolling window used both for the displayed min/max and for
  # deriving per-id trails.
  @window_ms 10_000
  # How long a track keeps being drawn after its last sighting (used for
  # the fade-out animation).
  @fade_ms 1_000
  # How far back the per-id trail extends.
  @trail_ms 4_000

  # Lightness range for the trail's per-segment color. The newest
  # segment (closest to the body circle) is rendered at `@trail_l_near`
  # — a touch darker than the body so it stays distinguishable from it
  # — and brightens linearly toward `@trail_l_far` for the oldest
  # segment, so the historical end of the path is the most prominent.
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

  # Velocity (m/s) → viewBox-unit scale for the velocity arrow. A 2 m/s
  # vector renders at ~80 viewBox units; faster vectors are clipped.
  @velocity_scale 40
  @velocity_max_len 100

  # Fixed palette of well-separated hues. The tracker reports at most a
  # handful of simultaneous targets, so 10 distinct hues are plenty;
  # longer-running sessions cycle through them via `rem/2`. Saturation
  # and lightness are shared across all targets so the only dimension
  # that varies between targets is hue, which gives the strongest
  # cross-target distinguishability.
  @hues [0, 36, 72, 108, 144, 180, 216, 252, 288, 324]
  @body_saturation 70
  @body_lightness 75

  # Padding (in meters) added around the data to avoid divide-by-zero
  # when the window is empty or all samples coincide.
  @minmax_pad_m 0.5

  # Ruler tick lengths in viewBox units. Minor ticks are every 10 cm;
  # major ticks land on full meters and are roughly 3× as long so they
  # remain visible and the operator can quickly count meters.
  @minor_tick_len 8
  @major_tick_len 24

  ## LiveView callbacks

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Radar.subscribe()

    devices = Radar.devices()
    selected = List.first(devices)
    selected_id = selected && selected.device_id

    {:ok,
     socket
     |> assign(:devices, devices)
     |> assign(:selected_device_id, selected_id)
     |> assign(:sensitivity, (selected && selected.sensitivity) || 4)
     |> assign(:bounds_mode, :static)
     |> assign(:static_bounds, compute_static_bounds(selected_id, devices))
     |> reset_radar_state()}
  end

  # Derive the static-mode rectangle for a selection. For a single
  # device we use that device's `*_cm` config. For `:all` we take the
  # union of every configured sensor's rectangle so the canvas
  # encompasses everything that could possibly be plotted.
  defp compute_static_bounds(nil, _devices), do: device_bounds(nil)

  defp compute_static_bounds(:all, []), do: device_bounds(nil)

  defp compute_static_bounds(:all, devices) do
    bounds = Enum.map(devices, &device_bounds/1)

    %{
      min_x: bounds |> Enum.map(& &1.min_x) |> Enum.min(),
      max_x: bounds |> Enum.map(& &1.max_x) |> Enum.max(),
      min_y: bounds |> Enum.map(& &1.min_y) |> Enum.min(),
      max_y: bounds |> Enum.map(& &1.max_y) |> Enum.max(),
      # range_m on the aggregate is unused — range circles in :all
      # mode are emitted per-sensor, not as a union.
      range_m: 0.0
    }
  end

  defp compute_static_bounds(device_id, devices) when is_integer(device_id) do
    devices |> Enum.find(&(&1.device_id == device_id)) |> device_bounds()
  end

  defp device_bounds(nil) do
    %{min_x: -1.0, max_x: 1.0, min_y: -1.0, max_y: 1.0, range_m: 1.0}
  end

  defp device_bounds(device) do
    %{
      min_x: device.x_neg_cm / 100.0,
      max_x: device.x_pos_cm / 100.0,
      min_y: device.y_neg_cm / 100.0,
      max_y: device.y_pos_cm / 100.0,
      range_m: device.range_cm / 100.0
    }
  end

  # Sensor → letter mapping for labels in :all mode. Device ids are
  # 1-based contiguous integers, so device 1 = "A", 2 = "B", etc.
  # Wraps around past Z, but in practice no installation has that many
  # radars on one host.
  defp device_letter(device_id) when is_integer(device_id) do
    <<?A + rem(device_id - 1, 26)>>
  end

  @impl true
  def handle_event("select_sensor", %{"device_id" => "all"}, socket) do
    {:noreply,
     socket
     |> assign(:selected_device_id, :all)
     |> assign(:static_bounds, compute_static_bounds(:all, socket.assigns.devices))
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
         |> assign(:static_bounds, compute_static_bounds(id, socket.assigns.devices))
         |> reset_radar_state()}

      _ ->
        {:noreply, socket}
    end
  end

  # Toggle between static (canvas matches the sensor's configured X/Y
  # rectangle) and auto (grow-only bounds derived from observed
  # samples). Switching to :auto seeds the bounds from the current
  # 10 s sample window so the canvas doesn't visually jump.
  def handle_event("toggle_bounds_mode", params, socket) do
    new_mode = if params["auto"] == "true", do: :auto, else: :static

    socket =
      socket
      |> assign(:bounds_mode, new_mode)
      |> apply_bounds_for_mode()
      |> rebuild_view()

    {:noreply, socket}
  end

  # The slider's value is the *intuitive* sensitivity (1=least, 9=most),
  # which is the inverse of the device's DPKTH scale (1=most sensitive,
  # 9=least). We translate here so the radar layer always sees the raw
  # device value. In :all mode the slider isn't shown, but we still
  # ignore the event defensively if a stray submission arrives.
  def handle_event("set_sensitivity", %{"sensitivity_ui" => ui_str}, socket) do
    with id when is_integer(id) <- socket.assigns.selected_device_id,
         {ui, ""} <- Integer.parse(ui_str),
         true <- ui in 1..9 do
      sensitivity = 10 - ui
      _ = Radar.set_sensitivity(id, sensitivity)

      {:noreply,
       socket
       |> assign(:sensitivity, sensitivity)
       |> reset_radar_state()}
    else
      _ -> {:noreply, socket}
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

  # "Fit bounds" snaps the (growing) display bounds back down to the
  # current 10 s sample window. After this, the bounds resume their
  # grow-only behavior from the freshly-tightened state.
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

  @impl true
  def handle_info({:radar_frame, device_id, %Frame{} = frame}, socket) do
    selected = socket.assigns.selected_device_id

    if selected == :all or selected == device_id do
      {:noreply, ingest_frame(socket, device_id, frame)}
    else
      {:noreply, socket}
    end
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
    |> assign(:ruler, empty_ruler())
    |> assign(:range_indicators, [])
    |> apply_bounds_for_mode()
    |> rebuild_view()
  end

  # Set the X/Y bounds appropriately for the current `:bounds_mode`.
  # In :static mode, snap to the configured rectangle. In :auto mode,
  # initialize from whatever data we currently hold (so a toggle from
  # static→auto doesn't immediately collapse to a tiny default range).
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

    new_samples =
      Enum.map(tracks, fn %Track{id: id, x: x, y: y, z: z} ->
        %{ts: now, device_id: device_id, id: id, x: x, y: y, z: z}
      end)

    samples =
      (new_samples ++ socket.assigns.samples)
      |> Enum.filter(&(&1.ts >= cutoff))

    # tracks_now is keyed by `{device_id, id}` so that two sensors
    # both reporting target id 1 don't merge into a single track.
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

  # In :static mode the X/Y bounds are pinned to the configured
  # rectangle and never change with the data. In :auto mode they grow
  # monotonically (see `grow_bounds/4`). Z always grows independently
  # since it isn't on the canvas.
  defp update_xy_bounds(%{bounds_mode: :static} = a, _new_samples) do
    {a.min_x, a.max_x, a.min_y, a.max_y}
  end

  defp update_xy_bounds(%{bounds_mode: :auto} = a, new_samples) do
    {min_x, max_x} = grow_bounds(new_samples, a.min_x, a.max_x, :x)
    {min_y, max_y} = grow_bounds(new_samples, a.min_y, a.max_y, :y)
    {min_x, max_x, min_y, max_y}
  end

  # Bounds are monotonically growing: once the visible range expands to
  # accommodate a sample, it never contracts on its own. Operators can
  # "Fit bounds" to snap the box back to the current 10 s data window
  # whenever they want a tighter view. Empty `new_samples` leave the
  # bounds untouched. The result is pre-padded so the rest of the
  # pipeline can treat stored bounds as display-ready.
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
  # samples. Called after frame ingest, after "Fit bounds", and after
  # mode toggles.
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
      build_range_indicators(
        a.devices,
        a.selected_device_id,
        min_x,
        max_x,
        min_y,
        max_y
      )

    socket
    |> assign(:view_targets, view_targets)
    |> assign(:ruler, ruler)
    |> assign(:range_indicators, range_indicators)
  end

  # Build one coverage ellipse per sensor in the current selection.
  # We use an ellipse rather than a circle because in :auto mode the X
  # and Y axes can scale non-uniformly, in which case a true circle in
  # world space is an ellipse on the canvas. In :static mode (typical
  # symmetric config) `rx == ry` and each entry draws as a circle.
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

    %{
      cx: scale(0.0, min_x, max_x, @vb),
      cy: scale(0.0, min_y, max_y, @vb),
      rx: range_m / (max_x - min_x) * @vb,
      ry: range_m / (max_y - min_y) * @vb
    }
  end

  defp compute_minmax([]) do
    # No data yet: provide a symmetric padded box around the origin so the
    # SVG still renders sensibly.
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

  # Used at render time to guarantee the canvas has a non-degenerate
  # range to scale into, even when no data has arrived yet (`nil`,
  # `nil`) or when all samples coincide.
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
    ~H"""
    <div class="container mx-auto p-4">
      <div class="card bg-base-100 shadow-md">
        <div class="card-body">
          <div class="flex items-center justify-between flex-wrap gap-4">
            <h1 class="card-title text-2xl">Radar</h1>
            <%= if @devices == [] do %>
              <span class="text-sm opacity-70">No radar sensors configured</span>
            <% else %>
              <form phx-change="select_sensor">
                <select id="radar-sensor" name="device_id" class="select select-bordered">
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
            <% end %>
          </div>

          <%= if @devices != [] do %>
            <div class="flex items-center flex-wrap gap-4 mt-2">
              <%= if @selected_device_id != :all do %>
                <form
                  phx-change="set_sensitivity"
                  class="flex items-center gap-3 grow min-w-0"
                >
                  <label for="radar-sensitivity" class="text-sm whitespace-nowrap">
                    Sensitivity
                  </label>
                  <span class="text-xs opacity-60">low</span>
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
                  <span class="text-xs opacity-60">high</span>
                  <span class="text-sm font-mono w-12 text-right">{10 - @sensitivity}/9</span>
                </form>
              <% end %>
              <form phx-change="toggle_bounds_mode">
                <label class="cursor-pointer label gap-2 py-0">
                  <input type="hidden" name="auto" value="false" />
                  <input
                    type="checkbox"
                    name="auto"
                    value="true"
                    class="toggle toggle-sm"
                    checked={@bounds_mode == :auto}
                  />
                  <span class="label-text">Auto-expand bounds</span>
                </label>
              </form>
              <%= if @bounds_mode == :auto do %>
                <button
                  id="radar-fit-bounds"
                  type="button"
                  class="btn btn-outline btn-sm"
                  phx-click="fit_bounds"
                >
                  Fit bounds
                </button>
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

          <div class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-5 gap-4 text-sm font-mono mt-2">
            <div>X: {fmt_m(@min_x)} … {fmt_m(@max_x)}</div>
            <div>Y: {fmt_m(@min_y)} … {fmt_m(@max_y)}</div>
            <div>Z: {fmt_m(@min_z)} … {fmt_m(@max_z)}</div>
            <div>Tracks: {map_size(@tracks_now)}</div>
            <div>Frame #: {@last_frame_number || "—"}</div>
          </div>

          <%= if @devices == [] do %>
            <div class="alert alert-info mt-4">
              <span>
                Configure at least one sensor under <code>:octopus, Octopus.Radar</code>
                in <code>config/config.exs</code>.
              </span>
            </div>
          <% else %>
            <div class="w-full max-w-3xl mx-auto aspect-square mt-4 bg-base-200 rounded">
              <svg viewBox="0 0 1000 1000" class="w-full h-full">
                <%= for r <- @range_indicators do %>
                  <ellipse
                    cx={fmt_f(r.cx)}
                    cy={fmt_f(r.cy)}
                    rx={fmt_f(r.rx)}
                    ry={fmt_f(r.ry)}
                    fill="rgba(37, 99, 235, 0.2)"
                    stroke="rgba(37, 99, 235, 0.5)"
                    stroke-width="1"
                  />
                <% end %>

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

                <%= for v <- @view_targets do %>
                  <g opacity={fmt_f(v.opacity)}>
                    <%= for seg <- v.trail do %>
                      <line
                        x1={fmt_f(seg.x1)}
                        y1={fmt_f(seg.y1)}
                        x2={fmt_f(seg.x2)}
                        y2={fmt_f(seg.y2)}
                        stroke={seg.color}
                        stroke-width="3"
                        stroke-linecap="round"
                      />
                    <% end %>
                    <line
                      x1={fmt_f(v.cx)}
                      y1={fmt_f(v.cy)}
                      x2={fmt_f(v.arrow_x)}
                      y2={fmt_f(v.arrow_y)}
                      stroke={v.color}
                      stroke-width="3"
                      stroke-linecap="round"
                    />
                    <circle
                      cx={fmt_f(v.arrow_x)}
                      cy={fmt_f(v.arrow_y)}
                      r="4"
                      fill={v.color}
                    />
                    <circle
                      cx={fmt_f(v.cx)}
                      cy={fmt_f(v.cy)}
                      r={fmt_f(v.radius)}
                      fill={v.color}
                      stroke="black"
                      stroke-width="2"
                    />
                    <text
                      x={fmt_f(v.cx)}
                      y={fmt_f(v.cy)}
                      text-anchor="middle"
                      dominant-baseline="central"
                      font-size="20"
                      font-weight="bold"
                      fill="black"
                    >
                      {v.label}
                    </text>
                  </g>
                <% end %>
              </svg>
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
      cx = scale(t.x, min_x, max_x, @vb)
      cy = scale(t.y, min_y, max_y, @vb)
      age = now - t.last_seen
      opacity = max(0.0, 1.0 - age / @fade_ms)

      arrow_dx = clamp(t.vx * @velocity_scale, -@velocity_max_len, @velocity_max_len)
      arrow_dy = clamp(t.vy * @velocity_scale, -@velocity_max_len, @velocity_max_len)

      hue = hue_for_track(device_id, id)

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
        color: color_for_track(device_id, id),
        arrow_x: cx + arrow_dx,
        arrow_y: cy + arrow_dy,
        trail: trail_segments
      }
    end)
  end

  # In :all mode every label is prefixed by the source sensor's letter
  # (A, B, C, …) so two sensors reporting the same numeric id are
  # visually distinguishable. In single-sensor mode the prefix would
  # be redundant clutter, so we omit it.
  defp track_label(device_id, id, :all), do: "#{device_letter(device_id)}#{id}"
  defp track_label(_device_id, id, _selected), do: Integer.to_string(id)

  # Pair consecutive samples (oldest-first) into per-segment line
  # records. Each segment carries a precomputed color whose lightness
  # is driven by the *newer* endpoint's age — so as a sample ages, the
  # segment touching it brightens smoothly.
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

  # Group samples by `{device_id, id}` and sort each group oldest-first
  # so that the resulting polyline runs from old position → newest
  # position. Composite keying makes trails from different sensors stay
  # separate even when their numeric ids collide.
  defp group_samples_by_key(samples, trail_cutoff) do
    samples
    |> Enum.filter(&(&1.ts >= trail_cutoff))
    |> Enum.group_by(&{&1.device_id, &1.id})
    |> Map.new(fn {key, ss} -> {key, Enum.sort_by(ss, & &1.ts)} end)
  end

  ## Ruler view model
  #
  # Two perpendicular axes through the world origin (0, 0), with tick
  # marks every 10 cm along both. Major ticks (multiples of 1 m) render
  # `@major_tick_len` long; minor ticks `@minor_tick_len`. The axis
  # lines themselves are only drawn when 0 actually lies inside the
  # currently-visible range — otherwise the axis would be off-canvas
  # anyway and a line stub at the edge looks misleading.
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

  # Enumerate every multiple of 10 cm inside `[lo_w, hi_w]` and emit a
  # short perpendicular tick at that position on the matching axis.
  # `axis_pos` is the canvas-space coordinate of the *other* axis (so
  # X-axis ticks all share `axis_pos = origin_y`).
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

  # Closer targets (smaller z) render with a larger radius, so a viewer
  # gets an intuitive "perspective" cue when reading the canvas.
  defp radius_for_z(z) do
    z = clamp(z, @z_min, @z_max)
    @r_max - (z - @z_min) / (@z_max - @z_min) * (@r_max - @r_min)
  end

  # Fixed-palette color assignment: cycle through `@hues` by a small
  # mix of device_id and target id. A hash-based scheme produces
  # near-identical hues for small consecutive integers (which is
  # exactly what the device's track ids are), so the mix here is just
  # `device_id * 7 + id` — multiplying by 7 (coprime with 10) ensures
  # different sensors land on different hue offsets in :all mode.
  defp hue_for_track(device_id, id) do
    Enum.at(@hues, rem(device_id * 7 + id, length(@hues)))
  end

  defp color_for_track(device_id, id),
    do: "hsl(#{hue_for_track(device_id, id)}, #{@body_saturation}%, #{@body_lightness}%)"

  # Per-segment trail color: the newest segment is `@trail_l_near` (a
  # bit darker than the body) and brightens linearly to `@trail_l_far`
  # for the oldest segment. So the historical tail of the path is the
  # most prominent, fading INTO the body rather than away from it.
  defp trail_color(hue, age_ms) do
    age_fraction = min(1.0, age_ms / @trail_ms)
    lightness = @trail_l_near + age_fraction * (@trail_l_far - @trail_l_near)
    "hsl(#{hue}, #{@body_saturation}%, #{round(lightness)}%)"
  end

  ## Formatting helpers

  defp fmt_m(nil), do: "—"
  defp fmt_m(v) when is_number(v), do: :erlang.float_to_binary(v / 1.0, decimals: 2) <> " m"

  # Trim float precision before it hits the DOM so diffs stay small and
  # the SVG attributes don't get noisy decimals.
  defp fmt_f(v) when is_integer(v), do: Integer.to_string(v)
  defp fmt_f(v) when is_float(v), do: :erlang.float_to_binary(v, decimals: 2)
end
