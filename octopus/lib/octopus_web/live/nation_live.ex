defmodule OctopusWeb.NationLive do
  @moduledoc """
  Combined pixel + radar live view for the Nation 2026 installation.

  Renders the LED ring panels (via Canvas 2D) and overlays real-time radar
  track data from the HLK-LD6001A-60G sensors, all in a single browser-side
  Canvas drawing loop.

  Architecture
  ============
  All rendering is performed client-side in `assets/js/hooks/nation.ts`. The
  server's only job is to push three types of events:

  * `"world:nation-<id>"` — installation geometry sent once on connect
  * `"frame:nation-<id>"` — raw pixel frame from the Mixer (immediate)
  * `"radar:nation-<id>"` — radar track list in world meters (coalesced)

  Radar frames arrive dozens of times per second from up to 6 sensors.  To
  avoid flooding the WebSocket, track state is updated on every frame but a
  `push_event` is issued at most once per `@render_interval_ms` (~15 fps).
  """

  use OctopusWeb, :live_view

  import Phoenix.LiveView, only: [connected?: 1, push_event: 3]

  alias Octopus.{Installation, Mixer, Radar}
  alias Octopus.Radar.{Frame, TrackMerge}

  @id_prefix "nation"

  # How long a track keeps being shown after its last sighting.
  @fade_ms 1_000
  # Rolling window kept in `tracks_now`.
  @window_ms 10_000
  # Maximum push rate for radar data (~15 fps).
  @render_interval_ms 66
  # Tracks whose XY speed is below this threshold are not shown.
  @velocity_min_m_s 0.05
  # Colour palette — identical to RadarLive so track colours are consistent
  # when operators compare the two views side by side.
  @hues [0, 36, 72, 108, 144, 180, 216, 252, 288, 324]
  @body_saturation 70
  @body_lightness 75

  @impl true
  def mount(_params, _session, socket) do
    radar_configured = Radar.configured?()
    clutter_filter = if radar_configured, do: Radar.view_settings().clutter_filter, else: false
    devices = if radar_configured, do: Radar.devices(), else: []

    socket =
      if connected?(socket) do
        Mixer.subscribe()

        if radar_configured do
          Radar.subscribe()
          Enum.each(devices, &Radar.subscribe_status(&1.device_id))
        end

        push_world_config(socket)
      else
        socket
      end

    {:ok,
     socket
     |> assign(:id, socket.id)
     |> assign(:id_prefix, @id_prefix)
     |> assign(:radar_configured, radar_configured)
     |> assign(:clutter_filter, clutter_filter)
     |> assign(:devices, devices)
     |> assign(:sensor_statuses, build_sensor_statuses(devices))
     |> assign(:tracks_now, %{})
     |> assign(:render_scheduled, false)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col w-full h-screen bg-base-200">
      <div class="shrink-0 flex items-center gap-4 px-4 py-2 border-b border-base-300 bg-base-100">
        <p class="text-xs font-semibold opacity-70">Nation 2026</p>
        <%= if @radar_configured do %>
          <div class="flex items-center gap-1">
            <%= for d <- @devices do %>
              <span
                class={["font-mono text-xs px-1.5 py-0.5 rounded border", sensor_status_class(@sensor_statuses[d.device_id])]}
                title={"Sensor #{device_letter(d.device_id)} · #{sensor_status_label(@sensor_statuses[d.device_id])}"}
              >
                {device_letter(d.device_id)}
              </span>
            <% end %>
          </div>
          <div class="flex items-center gap-2">
            <label for="nation-clutter-filter" class="text-xs font-semibold opacity-70">
              Clutter Filter
            </label>
            <input
              id="nation-clutter-filter"
              type="checkbox"
              class="toggle toggle-sm toggle-primary"
              checked={@clutter_filter}
              phx-click="toggle_clutter_filter"
            />
          </div>
        <% end %>
      </div>
      <div class="flex-1 min-h-0 flex items-center justify-center overflow-hidden">
        <canvas
          id={"#{@id_prefix}-#{@id}"}
          phx-hook="NationHook"
          phx-update="ignore"
          class="w-full h-full"
        />
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("toggle_clutter_filter", _params, socket) do
    if socket.assigns.radar_configured do
      Radar.toggle_clutter_filter()
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:mixer, {:frame, frame}}, socket) do
    {:noreply, push_frame(socket, frame)}
  end

  def handle_info({:mixer, _msg}, socket), do: {:noreply, socket}

  def handle_info({:radar_frame, device_id, %Frame{} = frame}, socket) do
    {:noreply, ingest_frame(socket, device_id, frame)}
  end

  def handle_info(:render, socket) do
    {:noreply, socket |> assign(:render_scheduled, false) |> push_radar_event()}
  end

  def handle_info({:view_settings_changed, settings}, socket) do
    {:noreply, assign(socket, :clutter_filter, settings.clutter_filter)}
  end

  def handle_info({:radar_sensor_status, device_id, new_status}, socket) do
    if Map.get(socket.assigns.sensor_statuses, device_id) == new_status do
      {:noreply, socket}
    else
      statuses = Map.put(socket.assigns.sensor_statuses, device_id, new_status)
      {:noreply, assign(socket, :sensor_statuses, statuses)}
    end
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  ## Private helpers

  defp push_world_config(socket) do
    {grid_w, grid_h} = Installation.panel_layout()

    panels =
      Installation.panel_positions_m(reference: :inner_face)
      |> Enum.map(&%{x: &1.x, y: &1.y, theta_deg: &1.theta_deg})

    # The face height (vertical extent of the pixel face) comes from the second
    # component of outer_dimensions_cm.  Fall back to panel_width_m (square
    # assumption) when the dimension is not available.
    panel_height_m =
      case Installation.panel_outer_dimensions_cm() do
        {_w, h, _d} -> h / 100.0
        _ -> Installation.panel_width_m()
      end

    push_event(socket, "world:#{@id_prefix}-#{socket.id}", %{
      world_radius_m: Installation.ring_radius_m(),
      platform_radius_m: Installation.platform_radius_m(),
      panel_width_m: Installation.panel_width_m(),
      panel_height_m: panel_height_m,
      panel_grid_w: grid_w,
      panel_grid_h: grid_h,
      panels: panels
    })
  end

  defp push_frame(socket, frame) do
    push_event(socket, "frame:#{@id_prefix}-#{socket.id}", %{frame: frame})
  end

  defp push_radar_event(socket) do
    now = System.monotonic_time(:millisecond)
    tracks = build_track_list(socket.assigns.tracks_now, now)
    push_event(socket, "radar:#{@id_prefix}-#{socket.id}", %{tracks: tracks})
  end

  defp build_track_list(tracks_now, now) do
    fusion_clusters = build_fusion_clusters(tracks_now)

    # Split into singleton tracks and per-cluster groups of merged tracks.
    {cluster_groups, singletons} =
      Enum.reduce(tracks_now, {%{}, []}, fn {{device_id, _} = key, t}, {clusters, singles} ->
        case Map.get(fusion_clusters, key) do
          %{cluster_id: cid, sensor_ids: sids} ->
            {Map.update(clusters, cid, [{t, device_id, sids}], &[{t, device_id, sids} | &1]),
             singles}

          nil ->
            {clusters, [{t, device_id} | singles]}
        end
      end)

    single_entries =
      Enum.map(singletons, fn {t, device_id} ->
        age = now - t.last_seen
        opacity = max(0.0, 1.0 - age / @fade_ms)

        %{
          x: t.x,
          y: t.y,
          vx: t.vx,
          vy: t.vy,
          opacity: Float.round(opacity, 3),
          color: sensor_color(device_id),
          merged: false,
          sensor_colors: [sensor_color(device_id)]
        }
      end)

    # Each cluster becomes one entry: averaged position + velocity, opacity
    # from the most recently seen member, pie colours from all sensor ids.
    merged_entries =
      Enum.map(cluster_groups, fn {_cid, members} ->
        n = length(members)
        avg = fn key -> Enum.sum(Enum.map(members, fn {t, _, _} -> Map.get(t, key) end)) / n end
        last_seen = Enum.max(Enum.map(members, fn {t, _, _} -> t.last_seen end))
        age = now - last_seen
        opacity = max(0.0, 1.0 - age / @fade_ms)
        {_, _, sensor_ids} = hd(members)

        %{
          x: Float.round(avg.(:x), 4),
          y: Float.round(avg.(:y), 4),
          vx: Float.round(avg.(:vx), 4),
          vy: Float.round(avg.(:vy), 4),
          opacity: Float.round(opacity, 3),
          color: sensor_color(elem(hd(members), 1)),
          merged: true,
          sensor_colors: Enum.map(sensor_ids, &sensor_color/1)
        }
      end)

    single_entries ++ merged_entries
  end

  # Mirrors `build_fusion_clusters/1` from RadarLive: returns a map of
  # track key → %{cluster_id, sensor_ids} for all fused tracks.
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
        sensor_ids =
          sources |> Enum.map(&TrackMerge.device_id/1) |> Enum.uniq() |> Enum.sort()

        Enum.map(sources, fn source ->
          {source.key, %{cluster_id: cluster_id, sensor_ids: sensor_ids}}
        end)
      end)
      |> Map.new()
    else
      %{}
    end
  end

  defp ingest_frame(socket, device_id, %Frame{tracks: tracks}) do
    now = System.monotonic_time(:millisecond)
    fade_cutoff = now - @fade_ms
    window_cutoff = now - @window_ms

    tracks_now =
      tracks
      |> Enum.filter(fn t -> :math.sqrt(t.vx * t.vx + t.vy * t.vy) >= @velocity_min_m_s end)
      |> Enum.reduce(socket.assigns.tracks_now, fn t, acc ->
        key = {device_id, t.id}
        prev = Map.get(acc, key)

        Map.put(acc, key, %{
          device_id: device_id,
          x: t.x,
          y: t.y,
          vx: t.vx,
          vy: t.vy,
          last_seen: now,
          first_seen: if(prev, do: prev.first_seen, else: now)
        })
      end)
      |> Enum.reject(fn {_key, t} ->
        t.last_seen < fade_cutoff or t.first_seen < window_cutoff
      end)
      |> Map.new()

    socket
    |> assign(:tracks_now, tracks_now)
    |> schedule_render()
  end

  defp schedule_render(%{assigns: %{render_scheduled: true}} = socket), do: socket

  defp schedule_render(socket) do
    Process.send_after(self(), :render, @render_interval_ms)
    assign(socket, :render_scheduled, true)
  end

  defp build_sensor_statuses(devices) do
    Map.new(devices, fn d -> {d.device_id, Radar.sensor_status(d.device_id)} end)
  end

  defp sensor_hue(device_id), do: Enum.at(@hues, rem(device_id * 7, length(@hues)))

  defp sensor_color(device_id),
    do: "hsl(#{sensor_hue(device_id)}, #{@body_saturation}%, #{@body_lightness}%)"

  defp device_letter(device_id), do: <<(?A + rem(device_id - 1, 26))>>

  defp sensor_status_class(:inactive),
    do: "text-gray-400 border-gray-300 bg-transparent"

  defp sensor_status_class(:unavailable),
    do: "bg-red-500 text-white border-red-600"

  defp sensor_status_class(:initializing),
    do: "bg-amber-400 text-white border-amber-500"

  defp sensor_status_class(:probing),
    do: "bg-cyan-500 text-white border-cyan-600"

  defp sensor_status_class(:working),
    do: "bg-green-500 text-white border-green-600"

  defp sensor_status_class(:stale),
    do: "bg-orange-500 text-white border-orange-600"

  defp sensor_status_class(:resetting),
    do: "bg-gray-900 text-white border-gray-700"

  defp sensor_status_class(_), do: sensor_status_class(:unavailable)

  defp sensor_status_label(:inactive), do: "Inactive"
  defp sensor_status_label(:unavailable), do: "Unavailable"
  defp sensor_status_label(:initializing), do: "Initializing"
  defp sensor_status_label(:probing), do: "Probing"
  defp sensor_status_label(:working), do: "Working"
  defp sensor_status_label(:stale), do: "No Data"
  defp sensor_status_label(:resetting), do: "Resetting"
  defp sensor_status_label(_), do: "Unknown"
end
