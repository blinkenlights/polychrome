defmodule OctopusWeb.RadarDebugLive do
  @moduledoc """
  Debug LiveView for radar sensors.

  Displays each configured sensor as a row. On the left is a labeled status
  button (same color coding as `RadarLive`). To the right is a 60-second
  rolling color history bar.

  ## History source

  The authoritative history lives in `Octopus.Radar.StatusHistory`, which
  subscribes to per-sensor status PubSub topics and records every transition
  with a wall-clock timestamp. On mount this LiveView fetches the current
  history from that GenServer and keeps a local copy that is updated in
  real-time via the same PubSub topic.

  ## Bar rendering

  The SVG viewBox is `0 0 600 32`. Each unit = 100 ms, so the full width
  represents exactly 60 seconds. Status transitions are placed at their
  100 ms-accurate position. Vertical grid lines appear every 10 units
  (= 1 second). The LEFT edge of the bar is always "now" (beside the
  sensor button); the right edge is 60 seconds ago.
  """

  use OctopusWeb, :live_view

  alias Octopus.Radar

  @window_ms 60_000
  @unit_ms 100
  @vb_width div(@window_ms, @unit_ms)
  @vb_height 32
  @units_per_second div(1_000, @unit_ms)
  @tick_ms 1_000

  @status_colors %{
    working: "#22c55e",
    stale: "#f97316",
    initializing: "#fbbf24",
    unavailable: "#ef4444",
    inactive: "#d1d5db"
  }

  ## LiveView callbacks

  @impl true
  def mount(_params, _session, socket) do
    devices = if Radar.enabled?(), do: Radar.devices(), else: []
    statuses = build_sensor_statuses(devices)
    histories = if Radar.enabled?(), do: Radar.get_history(), else: %{}

    if connected?(socket) do
      if Radar.enabled?() do
        Enum.each(devices, &Radar.subscribe_status(&1.device_id))
      end

      :timer.send_interval(@tick_ms, :tick)
    end

    {:ok,
     assign(socket,
       radar_enabled: Radar.enabled?(),
       devices: devices,
       statuses: statuses,
       histories: histories,
       now_ms: System.system_time(:millisecond),
       vb_width: @vb_width,
       vb_height: @vb_height,
       window_ms: @window_ms,
       units_per_second: @units_per_second
     )}
  end

  @impl true
  def handle_info({:radar_sensor_status, device_id, new_status}, socket) do
    now = System.system_time(:millisecond)
    cutoff = now - @window_ms

    histories =
      Map.update(socket.assigns.histories, device_id, [{now, new_status}], fn entries ->
        trim_entries([{now, new_status} | entries], cutoff)
      end)

    statuses = Map.put(socket.assigns.statuses, device_id, new_status)
    {:noreply, assign(socket, histories: histories, statuses: statuses, now_ms: now)}
  end

  def handle_info(:tick, socket) do
    now = System.system_time(:millisecond)
    cutoff = now - @window_ms

    histories =
      Map.new(socket.assigns.histories, fn {device_id, entries} ->
        {device_id, trim_entries(entries, cutoff)}
      end)

    {:noreply, assign(socket, histories: histories, now_ms: now)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  ## Rendering

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-4">
      <div class="flex items-center gap-4 mb-4">
        <h1 class="text-xl font-bold">Radar Debug</h1>
        <a href="/radar" class="btn btn-outline btn-sm">← Radar</a>
      </div>

      <%= if not @radar_enabled do %>
        <p class="text-gray-500">Radar is not enabled.</p>
      <% else %>
        <div class="flex items-center gap-2 mb-3 text-xs text-gray-500">
          <div class="flex gap-3">
            <%= for {status, color} <- status_legend() do %>
              <span class="flex items-center gap-1">
                <span class="inline-block w-3 h-3 rounded-sm" style={"background:#{color}"}></span>
                {status_label(status)}
              </span>
            <% end %>
          </div>
          <span class="ml-auto">now ← &nbsp;&nbsp; 60 s ago →</span>
        </div>

        <div class="flex flex-col gap-1">
          <%= for device <- @devices do %>
            <div class="flex items-center gap-3">
              <div class="w-32 shrink-0">
                <button
                  type="button"
                  class={[
                    "btn btn-sm font-mono w-full justify-start",
                    sensor_status_class(@statuses[device.device_id])
                  ]}
                  title={"Sensor #{device_letter(device.device_id)} (#{device.port}) — #{status_label(@statuses[device.device_id])}"}
                >
                  {device_letter(device.device_id)}
                  <span class="text-xs ml-1 opacity-80 truncate">
                    {status_label(@statuses[device.device_id])}
                  </span>
                </button>
              </div>
              <div class="flex-1">
                <svg
                  width="100%"
                  height={@vb_height}
                  viewBox={"0 0 #{@vb_width} #{@vb_height}"}
                  preserveAspectRatio="none"
                  xmlns="http://www.w3.org/2000/svg"
                  style="display:block"
                >
                  <%= for {x, w, status} <- build_segments(
                        Map.get(@histories, device.device_id, []),
                        @now_ms - @window_ms,
                        @now_ms
                      ) do %>
                    <rect
                      x={x}
                      y="0"
                      width={max(w, 1)}
                      height={@vb_height}
                      fill={status_color(status)}
                    />
                  <% end %>
                  <%= for s <- 1..59 do %>
                    <line
                      x1={s * @units_per_second}
                      y1="0"
                      x2={s * @units_per_second}
                      y2={@vb_height}
                      stroke="rgba(0,0,0,0.18)"
                      stroke-width="0.6"
                    />
                  <% end %>
                </svg>
              </div>
            </div>
          <% end %>
        </div>

        <div class="ml-[8.75rem] mt-1">
          <svg
            width="100%"
            height="14"
            viewBox={"0 0 #{@vb_width} 14"}
            preserveAspectRatio="none"
            xmlns="http://www.w3.org/2000/svg"
            style="display:block"
          >
            <%= for s <- [10, 20, 30, 40, 50, 60] do %>
              <text
                x={s * @units_per_second}
                y="11"
                font-size="9"
                fill="#9ca3af"
                text-anchor="middle"
              >{s}s</text>
            <% end %>
          </svg>
        </div>
      <% end %>
    </div>
    """
  end

  ## Private helpers

  # Converts a newest-first history list into [{x, width, status}] SVG segments
  # where each unit = @unit_ms ms, x=0 is NOW (left edge), x=@vb_width is 60s ago (right edge).
  defp build_segments(history, window_start, now_ms) do
    sorted = Enum.sort_by(history, fn {t, _} -> t end)

    anchor_status =
      sorted
      |> Enum.filter(fn {t, _} -> t <= window_start end)
      |> List.last()
      |> case do
        nil -> :inactive
        {_, s} -> s
      end

    in_window = Enum.filter(sorted, fn {t, _} -> t > window_start end)

    # Reduce oldest-to-newest. seg_x starts at @vb_width (rightmost = oldest edge) and
    # moves left as we process newer events. For each event, the segment to the right of
    # x (from x to seg_x) has the previous status (seg_status).
    {last_x, last_status, rev_segs} =
      Enum.reduce(in_window, {@vb_width, anchor_status, []}, fn {event_time, event_status},
                                                                 {seg_x, seg_status, segs} ->
        x = max(div(now_ms - event_time, @unit_ms), 0)

        segs =
          if seg_x > x do
            [{x, seg_x - x, seg_status} | segs]
          else
            segs
          end

        {x, event_status, segs}
      end)

    # Final segment from x=0 (now) to last_x covers the most recent status.
    rev_segs =
      if last_x > 0 do
        [{0, last_x, last_status} | rev_segs]
      else
        rev_segs
      end

    Enum.reverse(rev_segs)
  end

  defp trim_entries(entries, cutoff) do
    case Enum.split_while(entries, fn {t, _} -> t >= cutoff end) do
      {recent, []} -> recent
      {recent, [anchor | _]} -> recent ++ [anchor]
    end
  end

  defp build_sensor_statuses(devices) do
    Map.new(devices, fn d -> {d.device_id, Radar.sensor_status(d.device_id)} end)
  end

  defp device_letter(device_id), do: <<(?A + device_id - 1)::utf8>>

  defp status_color(status), do: Map.get(@status_colors, status, "#d1d5db")

  defp status_label(:inactive), do: "Inactive"
  defp status_label(:unavailable), do: "Unavailable"
  defp status_label(:initializing), do: "Initializing"
  defp status_label(:working), do: "Working"
  defp status_label(:stale), do: "No Data"
  defp status_label(_), do: "Unknown"

  defp status_legend do
    [
      {:working, @status_colors.working},
      {:stale, @status_colors.stale},
      {:initializing, @status_colors.initializing},
      {:unavailable, @status_colors.unavailable},
      {:inactive, @status_colors.inactive}
    ]
  end

  defp sensor_status_class(:inactive),
    do: "bg-white text-gray-600 border border-gray-300"

  defp sensor_status_class(:unavailable),
    do: "bg-red-500 text-white border-red-600"

  defp sensor_status_class(:initializing),
    do: "bg-amber-400 text-white border-amber-500"

  defp sensor_status_class(:working),
    do: "bg-green-500 text-white border-green-600"

  defp sensor_status_class(:stale),
    do: "bg-orange-500 text-white border-orange-600"

  defp sensor_status_class(_), do: sensor_status_class(:unavailable)
end
