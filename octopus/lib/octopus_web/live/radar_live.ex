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
  @r_min 12
  @r_max 36

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

  ## LiveView callbacks

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Radar.subscribe()

    devices = Radar.devices()

    selected =
      case List.first(devices) do
        nil -> nil
        %{device_id: id} -> id
      end

    {:ok,
     socket
     |> assign(:devices, devices)
     |> assign(:selected_device_id, selected)
     |> reset_radar_state()}
  end

  @impl true
  def handle_event("select_sensor", %{"device_id" => id_str}, socket) do
    case Integer.parse(id_str) do
      {id, ""} ->
        {:noreply,
         socket
         |> assign(:selected_device_id, id)
         |> reset_radar_state()}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:radar_frame, device_id, %Frame{} = frame}, socket) do
    if device_id == socket.assigns.selected_device_id do
      {:noreply, ingest_frame(socket, frame)}
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
    |> assign(:min_x, nil)
    |> assign(:max_x, nil)
    |> assign(:min_y, nil)
    |> assign(:max_y, nil)
    |> assign(:min_z, nil)
    |> assign(:max_z, nil)
    |> assign(:view_targets, [])
  end

  defp ingest_frame(socket, %Frame{tracks: tracks, frame_number: frame_number}) do
    now = System.monotonic_time(:millisecond)
    cutoff = now - @window_ms
    fade_cutoff = now - @fade_ms

    new_samples =
      Enum.map(tracks, fn %Track{id: id, x: x, y: y, z: z} ->
        %{ts: now, id: id, x: x, y: y, z: z}
      end)

    samples =
      (new_samples ++ socket.assigns.samples)
      |> Enum.filter(&(&1.ts >= cutoff))

    tracks_now =
      tracks
      |> Enum.reduce(socket.assigns.tracks_now, fn %Track{} = t, acc ->
        Map.put(acc, t.id, %{
          x: t.x,
          y: t.y,
          z: t.z,
          vx: t.vx,
          vy: t.vy,
          last_seen: now
        })
      end)
      |> Enum.reject(fn {_id, t} -> t.last_seen < fade_cutoff end)
      |> Map.new()

    {min_x, max_x, min_y, max_y, min_z, max_z} = compute_minmax(samples)

    view_targets =
      build_view_targets(%{
        tracks_now: tracks_now,
        samples: samples,
        min_x: min_x,
        max_x: max_x,
        min_y: min_y,
        max_y: max_y
      })

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
    |> assign(:view_targets, view_targets)
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
                      Sensor {d.device_id} ({d.port})
                    </option>
                  <% end %>
                </select>
              </form>
            <% end %>
          </div>

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
                      {v.id}
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
      max_y: max_y
    } = assigns

    now = System.monotonic_time(:millisecond)
    trail_cutoff = now - @trail_ms

    samples_by_id = group_samples_by_id(samples, trail_cutoff)

    Enum.map(tracks_now, fn {id, t} ->
      cx = scale(t.x, min_x, max_x, @vb)
      cy = scale(t.y, min_y, max_y, @vb)
      age = now - t.last_seen
      opacity = max(0.0, 1.0 - age / @fade_ms)

      arrow_dx = clamp(t.vx * @velocity_scale, -@velocity_max_len, @velocity_max_len)
      arrow_dy = clamp(t.vy * @velocity_scale, -@velocity_max_len, @velocity_max_len)

      trail_segments =
        samples_by_id
        |> Map.get(id, [])
        |> build_trail_segments(now, hue_for_id(id), min_x, max_x, min_y, max_y)

      %{
        id: id,
        cx: cx,
        cy: cy,
        radius: radius_for_z(t.z),
        opacity: opacity,
        color: color_for_id(id),
        arrow_x: cx + arrow_dx,
        arrow_y: cy + arrow_dy,
        trail: trail_segments
      }
    end)
  end

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

  # Group samples by id and sort each group oldest-first so that the
  # resulting polyline runs from old position → newest position.
  defp group_samples_by_id(samples, trail_cutoff) do
    samples
    |> Enum.filter(&(&1.ts >= trail_cutoff))
    |> Enum.group_by(& &1.id)
    |> Map.new(fn {id, ss} -> {id, Enum.sort_by(ss, & &1.ts)} end)
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

  # Fixed-palette color assignment: cycle through `@hues` by id. A
  # hash-based scheme produces near-identical hues for small consecutive
  # integers (which is exactly what the device's track ids are), so a
  # plain modulo lookup gives noticeably better separation in practice.
  defp hue_for_id(id), do: Enum.at(@hues, rem(id, length(@hues)))

  defp color_for_id(id),
    do: "hsl(#{hue_for_id(id)}, #{@body_saturation}%, #{@body_lightness}%)"

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
