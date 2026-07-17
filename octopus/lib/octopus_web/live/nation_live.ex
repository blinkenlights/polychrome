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
  alias Octopus.Radar.Frame

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

    socket =
      if connected?(socket) do
        Mixer.subscribe()

        if radar_configured do
          Radar.subscribe()
        end

        push_world_config(socket)
      else
        socket
      end

    {:ok,
     socket
     |> assign(:id, socket.id)
     |> assign(:radar_configured, radar_configured)
     |> assign(:clutter_filter, clutter_filter)
     |> assign(:tracks_now, %{})
     |> assign(:render_scheduled, false)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col w-full h-screen bg-black">
      <div class="shrink-0 flex items-center gap-4 px-4 py-2 border-b border-base-300 bg-base-100">
        <p class="text-xs font-semibold opacity-70">Nation 2026</p>
        <%= if @radar_configured do %>
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

  def handle_info(_msg, socket), do: {:noreply, socket}

  ## Private helpers

  defp push_world_config(socket) do
    {grid_w, grid_h} = Installation.panel_layout()

    panels =
      Installation.panel_positions_m(reference: :body_center)
      |> Enum.map(&%{x: &1.x, y: &1.y, theta_deg: &1.theta_deg})

    push_event(socket, "world:#{@id_prefix}-#{socket.id}", %{
      world_radius_m: Installation.ring_radius_m(),
      platform_radius_m: Installation.platform_radius_m(),
      panel_width_m: Installation.panel_width_m(),
      panel_depth_m: Installation.panel_depth_m(),
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
    Enum.map(tracks_now, fn {{device_id, _id}, t} ->
      age = now - t.last_seen
      opacity = max(0.0, 1.0 - age / @fade_ms)

      %{
        x: t.x,
        y: t.y,
        vx: t.vx,
        vy: t.vy,
        opacity: Float.round(opacity, 3),
        color: sensor_color(device_id)
      }
    end)
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

  defp sensor_hue(device_id), do: Enum.at(@hues, rem(device_id * 7, length(@hues)))

  defp sensor_color(device_id),
    do: "hsl(#{sensor_hue(device_id)}, #{@body_saturation}%, #{@body_lightness}%)"
end
