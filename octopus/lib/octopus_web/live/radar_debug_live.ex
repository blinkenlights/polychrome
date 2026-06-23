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

  ## Halt / dump

  The Halt button freezes the display at the current moment and emits a
  compact JSON log entry tagged `RADAR-DUMP[<halt-id>]` containing the full
  stored history (up to one hour) for all sensors. The halt-id
  (`halt-YYYYMMDDTHHMMSSZ`) can be used to grep the logs or reference the
  snapshot in conversation. Clicking Resume re-fetches live history and
  resumes real-time updates.
  """

  use OctopusWeb, :live_view

  require Logger

  alias Octopus.Radar

  @display_window_ms 60_000
  @unit_ms 100
  @vb_width div(@display_window_ms, @unit_ms)
  @vb_height 32
  @units_per_second div(1_000, @unit_ms)
  @tick_ms 1_000

  @status_colors %{
    working: "#22c55e",
    stale: "#f97316",
    initializing: "#fbbf24",
    unavailable: "#ef4444",
    inactive: "#d1d5db",
    resetting: "#111827"
  }

  ## LiveView callbacks

  @impl true
  def mount(_params, _session, socket) do
    devices = if Radar.enabled?(), do: Radar.devices(), else: []
    statuses = build_sensor_statuses(devices)
    histories = if Radar.enabled?(), do: trim_histories(Radar.get_history(), @display_window_ms), else: %{}

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
       adapters: Radar.adapters(),
       now_ms: System.system_time(:millisecond),
       halted: false,
       halt_id: nil,
       vb_width: @vb_width,
       vb_height: @vb_height,
       window_ms: @display_window_ms,
       units_per_second: @units_per_second
     )}
  end

  @impl true
  def handle_event("toggle_halt", _, %{assigns: %{halted: false}} = socket) do
    halt_id = generate_halt_id()
    emit_dump(halt_id)
    {:noreply, assign(socket, halted: true, halt_id: halt_id)}
  end

  def handle_event("toggle_halt", _, %{assigns: %{halted: true}} = socket) do
    now = System.system_time(:millisecond)

    histories =
      if Radar.enabled?() do
        trim_histories(Radar.get_history(), @display_window_ms)
      else
        %{}
      end

    statuses = build_sensor_statuses(socket.assigns.devices)
    {:noreply, assign(socket, halted: false, halt_id: nil, histories: histories, statuses: statuses, now_ms: now)}
  end

  @impl true
  def handle_event("reset_adapter", %{"adapter" => name}, socket) do
    Radar.reset_adapter(name)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:radar_sensor_status, _device_id, _new_status}, %{assigns: %{halted: true}} = socket) do
    {:noreply, socket}
  end

  def handle_info({:radar_sensor_status, device_id, new_status}, socket) do
    now = System.system_time(:millisecond)
    cutoff = now - @display_window_ms

    histories =
      Map.update(socket.assigns.histories, device_id, [{now, new_status}], fn entries ->
        trim_entries([{now, new_status} | entries], cutoff)
      end)

    statuses = Map.put(socket.assigns.statuses, device_id, new_status)
    {:noreply, assign(socket, histories: histories, statuses: statuses, now_ms: now)}
  end

  def handle_info(:tick, %{assigns: %{halted: true}} = socket) do
    {:noreply, socket}
  end

  def handle_info(:tick, socket) do
    now = System.system_time(:millisecond)
    cutoff = now - @display_window_ms

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
        <%= if @adapters != [] do %>
          <div class="flex items-center gap-2 ml-2">
            <%= for adapter <- @adapters do %>
              <button
                type="button"
                phx-click="reset_adapter"
                phx-value-adapter={adapter.name}
                class="btn btn-sm btn-outline font-mono"
                title={"USB reset adapter "#{adapter.name}" (#{adapter.usb_path}) — power-cycles sensors #{Enum.map_join(adapter.device_ids, ", ", &device_letter/1)}"}
              >
                ↺ USB "<%= adapter.name %>"
              </button>
            <% end %>
          </div>
        <% end %>
        <button
          type="button"
          phx-click="toggle_halt"
          class={[
            "btn btn-sm ml-auto",
            if(@halted, do: "btn-success", else: "btn-warning")
          ]}
        >
          <%= if @halted do %>▶ Resume<% else %>⏸ Halt<% end %>
        </button>
      </div>

      <%= if @halted do %>
        <div class="flex items-center gap-2 mb-3 px-2 py-1.5 bg-amber-50 border border-amber-200 rounded text-xs text-amber-800">
          <span class="font-semibold">Frozen snapshot</span>
          <span class="font-mono">{@halt_id}</span>
          <span class="text-amber-600">— full history dumped to log</span>
        </div>
      <% end %>

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
          <span class="ml-auto">
            now ← &nbsp;&nbsp; 60 s ago →
            <%= if @halted do %><span class="text-amber-600 font-semibold ml-2">(frozen)</span><% end %>
          </span>
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
                  <%= for {x, major} <- ruler_lines(@now_ms, @units_per_second, @vb_width) do %>
                    <line
                      x1={x}
                      y1="0"
                      x2={x}
                      y2={@vb_height}
                      stroke={if major, do: "rgba(0,0,0,0.45)", else: "rgba(0,0,0,0.15)"}
                      stroke-width={if major, do: "1.8", else: "0.5"}
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

  defp generate_halt_id do
    now = DateTime.utc_now()
    Calendar.strftime(now, "halt-%Y%m%dT%H%M%SZ")
  end

  defp emit_dump(halt_id) do
    history = if Radar.enabled?(), do: Radar.get_history(), else: %{}

    sensors =
      Map.new(history, fn {device_id, entries} ->
        letter = device_letter(device_id)
        # Oldest first for readability in the dump
        pairs = entries |> Enum.reverse() |> Enum.map(fn {t, s} -> [t, Atom.to_string(s)] end)
        {letter, pairs}
      end)

    payload = Jason.encode!(%{"captured_at" => DateTime.to_iso8601(DateTime.utc_now()), "sensors" => sensors})
    Logger.info("RADAR-DUMP[#{halt_id}] #{payload}")
  end

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

  # Returns [{x, major?}] for all wall-clock-aligned 1-second divider lines
  # that fall within the SVG viewport. x is a float in SVG units. Lines where
  # the underlying wall-clock second is divisible by 10 are marked :major and
  # rendered thicker. Because x is derived from `now_ms` every tick, the lines
  # shift leftward continuously, making elapsed time visible even when no state
  # transition has occurred.
  defp ruler_lines(now_ms, units_per_second, vb_width) do
    units_per_ms = units_per_second / 1_000.0
    # Distance from "now" (x=0) to the most recent whole second, in SVG units
    sec_offset = rem(now_ms, 1_000) * units_per_ms
    # Which step index i corresponds to a 10s wall-clock boundary:
    # boundary at i steps back == second (floor(now/1000) - i), major when divisible by 10.
    sec_index = rem(div(now_ms, 1_000), 10)

    for i <- 0..61,
        x = sec_offset + i * units_per_second,
        x > 0.0,
        x < vb_width do
      {x, rem(i, 10) == sec_index}
    end
  end

  defp trim_histories(history, window_ms) do
    now = System.system_time(:millisecond)
    cutoff = now - window_ms
    Map.new(history, fn {id, entries} -> {id, trim_entries(entries, cutoff)} end)
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
  defp status_label(:resetting), do: "Resetting"
  defp status_label(_), do: "Unknown"

  defp status_legend do
    [
      {:working, @status_colors.working},
      {:stale, @status_colors.stale},
      {:initializing, @status_colors.initializing},
      {:unavailable, @status_colors.unavailable},
      {:resetting, @status_colors.resetting},
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

  defp sensor_status_class(:resetting),
    do: "bg-gray-900 text-white border-gray-800"

  defp sensor_status_class(_), do: sensor_status_class(:unavailable)
end
