defmodule OctopusWeb.RadarDebugLive do
  @moduledoc """
  Debug LiveView for radar sensors.

  Displays each configured sensor as a row. On the left is a labeled status
  button (same color coding as `RadarLive`). To the right is a 120-second
  rolling color history bar.

  ## History source

  The authoritative history lives in `Octopus.Radar.StatusHistory`, which
  subscribes to per-sensor status PubSub topics and records every transition
  with a wall-clock timestamp. On mount this LiveView fetches the current
  history from that GenServer and keeps a local copy that is updated in
  real-time via the same PubSub topic.

  ## Bar rendering

  The SVG viewBox is `0 0 1200 32`. Each unit = 100 ms, so the full width
  represents exactly 120 seconds. Status transitions are placed at their
  100 ms-accurate position. Vertical grid lines appear every 10 units
  (= 1 second), thicker every 100 units (= 10 seconds). Grid lines are
  wall-clock aligned and shift rightward each tick so elapsed time is
  visible even without state changes. The LEFT edge is always "now";
  the right edge is 120 seconds ago.

  ## Snapshots

  The Snapshot button captures the current timeline state as a static
  frozen row below the live view. Multiple snapshots accumulate; each has
  an × Delete button. Snapshots do not affect the live timeline.

  ## Copy Dump

  The Copy Dump button generates a compact JSON payload covering the full
  stored history (up to one hour) for all sensors, logs it with a
  `RADAR-DUMP[<id>]` tag, and also copies it to the clipboard.
  """

  use OctopusWeb, :live_view

  require Logger

  alias Octopus.Radar

  @display_window_ms 120_000
  @unit_ms 100
  @vb_width div(@display_window_ms, @unit_ms)
  @vb_height 32
  @units_per_second div(1_000, @unit_ms)
  @tick_ms 1_000

  @status_colors %{
    working: "#22c55e",
    stale: "#f97316",
    initializing: "#fbbf24",
    probing: "#06b6d4",
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
    stats = if Radar.enabled?(), do: Radar.get_stats(), else: %{}

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
       stats: stats,
       adapters: Radar.adapters(),
       snapshots: [],
       dump_json: generate_dump_json(generate_dump_id()),
       now_ms: System.system_time(:millisecond),
       vb_width: @vb_width,
       vb_height: @vb_height,
       window_ms: @display_window_ms,
       units_per_second: @units_per_second
     )}
  end

  @impl true
  def handle_event("take_snapshot", _, socket) do
    now = System.system_time(:millisecond)
    snap_id = generate_snap_id()

    histories =
      if Radar.enabled?() do
        trim_histories(Radar.get_history(), @display_window_ms)
      else
        socket.assigns.histories
      end

    snapshot = %{
      id: snap_id,
      now_ms: now,
      captured_label: Calendar.strftime(DateTime.utc_now(), "%Y-%m-%d %H:%M:%S UTC"),
      histories: histories,
      statuses: socket.assigns.statuses,
      dump_json: generate_dump_json("#{snap_id}-dump", histories)
    }

    {:noreply, assign(socket, snapshots: socket.assigns.snapshots ++ [snapshot])}
  end

  def handle_event("delete_snapshot", %{"id" => snap_id}, socket) do
    snapshots = Enum.reject(socket.assigns.snapshots, fn s -> s.id == snap_id end)
    {:noreply, assign(socket, snapshots: snapshots)}
  end

  def handle_event("copy_dump", %{"snap_id" => snap_id}, socket) do
    dump_id = "#{snap_id}-dump"

    json =
      case Enum.find(socket.assigns.snapshots, &(&1.id == snap_id)) do
        nil -> generate_dump_json(dump_id)
        snapshot -> snapshot.dump_json
      end

    Logger.info("RADAR-DUMP[#{dump_id}] #{json}")
    {:noreply, socket}
  end

  def handle_event("copy_dump", _params, socket) do
    dump_id = generate_dump_id()
    Logger.info("RADAR-DUMP[#{dump_id}] #{generate_dump_json(dump_id)}")
    {:noreply, socket}
  end

  def handle_event("toggle_sensor", %{"device_id" => id_str}, socket) do
    case Integer.parse(id_str) do
      {id, ""} ->
        status = Map.get(socket.assigns.statuses, id, :unavailable)

        if status == :inactive do
          Radar.enable_sensor(id)
        else
          Radar.disable_sensor(id)
        end

        statuses = build_sensor_statuses(socket.assigns.devices)
        {:noreply, assign(socket, statuses: statuses)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("reset_adapter", %{"adapter" => name}, socket) do
    Radar.reset_adapter(name)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:radar_sensor_status, device_id, new_status}, socket) do
    now = System.system_time(:millisecond)
    cutoff = now - @display_window_ms

    histories =
      Map.update(socket.assigns.histories, device_id, [{now, new_status}], fn entries ->
        trim_entries([{now, new_status} | entries], cutoff)
      end)

    statuses = Map.put(socket.assigns.statuses, device_id, new_status)
    {:noreply, assign(socket, histories: histories, statuses: statuses, stats: Radar.get_stats(), now_ms: now)}
  end

  def handle_info(:tick, socket) do
    now = System.system_time(:millisecond)
    cutoff = now - @display_window_ms

    histories =
      Map.new(socket.assigns.histories, fn {device_id, entries} ->
        {device_id, trim_entries(entries, cutoff)}
      end)

    {:noreply,
     assign(socket,
       histories: histories,
       stats: if(socket.assigns.radar_enabled, do: Radar.get_stats(), else: socket.assigns.stats),
       now_ms: now,
       dump_json: generate_dump_json(generate_dump_id())
     )}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  ## Rendering

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-4">
      <div class="flex items-center gap-4 mb-4 flex-wrap">
        <h1 class="text-xl font-bold">Radar Debug</h1>
        <a href="/radar" class="btn btn-outline btn-sm">← Radar</a>
        <%= if @adapters != [] do %>
          <div class="flex items-center gap-2">
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
        <div class="ml-auto flex items-center gap-2">
          <button type="button" id="copy-dump-main" phx-hook="CopyDump" data-dump={@dump_json} class="btn btn-sm btn-outline" title="Generate full 1-hour JSON dump, log it, and copy to clipboard">
            📋 Copy Dump
          </button>
          <button type="button" phx-click="take_snapshot" class="btn btn-sm btn-warning">
            📸 Snapshot
          </button>
        </div>
      </div>

      <%= if not @radar_enabled do %>
        <p class="text-gray-500">Radar is not enabled.</p>
      <% else %>
        <.stats_panel devices={@devices} stats={@stats} />

        <div class="flex items-center gap-2 mb-3 text-xs text-gray-500">
          <div class="flex gap-3">
            <%= for {status, color} <- status_legend() do %>
              <span class="flex items-center gap-1">
                <span class="inline-block w-3 h-3 rounded-sm" style={"background:#{color}"}></span>
                {status_label(status)}
              </span>
            <% end %>
          </div>
          <span class="ml-auto">now ← &nbsp;&nbsp; 120 s ago →</span>
        </div>

        <.timeline_rows
          devices={@devices}
          statuses={@statuses}
          histories={@histories}
          now_ms={@now_ms}
          vb_width={@vb_width}
          vb_height={@vb_height}
          units_per_second={@units_per_second}
          window_ms={@window_ms}
          interactive={true}
        />

        <.timeline_ruler
          now_ms={@now_ms}
          vb_width={@vb_width}
          units_per_second={@units_per_second}
          window_ms={@window_ms}
        />

        <%= for snapshot <- @snapshots do %>
          <.snapshot_section
            snapshot={snapshot}
            devices={@devices}
            vb_width={@vb_width}
            vb_height={@vb_height}
            units_per_second={@units_per_second}
            window_ms={@window_ms}
          />
        <% end %>
      <% end %>
    </div>
    """
  end

  defp stats_panel(assigns) do
    assigns =
      assign(assigns,
        statuses_order: stats_statuses_order(),
        total: aggregate_stats(assigns.devices, assigns.stats)
      )

    ~H"""
    <div class="mb-4 border border-gray-200 rounded-lg overflow-hidden">
      <div class="px-3 py-2 bg-gray-50 border-b border-gray-200 text-sm font-semibold">
        Sensor Statistics <span class="text-xs font-normal text-gray-400">(since startup)</span>
      </div>
      <div class="overflow-x-auto">
        <table class="w-full text-xs">
          <thead>
            <tr class="text-gray-500 text-left">
              <th class="px-3 py-1 font-medium">Sensor</th>
              <th class="px-3 py-1 font-medium">Uptime</th>
              <th class="px-3 py-1 font-medium">Working</th>
              <th class="px-3 py-1 font-medium">Dropouts</th>
              <th class="px-3 py-1 font-medium">Retries</th>
              <th class="px-3 py-1 font-medium">Time per state (total · avg)</th>
            </tr>
          </thead>
          <tbody>
            <%= for device <- @devices do %>
              <% s = sensor_stat(@stats, device.device_id) %>
              <tr class="border-t border-gray-100">
                <td class="px-3 py-1 font-mono font-semibold">{device_letter(device.device_id)}</td>
                <td class="px-3 py-1 font-mono">{format_duration_ms(s.total_ms)}</td>
                <td class="px-3 py-1 font-mono">{working_pct(s)}%</td>
                <td class="px-3 py-1 font-mono">{s.dropouts}</td>
                <td class="px-3 py-1 font-mono">{s.retries}</td>
                <td class="px-3 py-1">
                  <.state_breakdown stats={s} statuses_order={@statuses_order} />
                </td>
              </tr>
            <% end %>
            <tr class="border-t-2 border-gray-300 bg-gray-50">
              <td class="px-3 py-1 font-semibold">Total</td>
              <td class="px-3 py-1 font-mono">{format_duration_ms(@total.total_ms)}</td>
              <td class="px-3 py-1 font-mono">{working_pct(@total)}%</td>
              <td class="px-3 py-1 font-mono">{@total.dropouts}</td>
              <td class="px-3 py-1 font-mono">{@total.retries}</td>
              <td class="px-3 py-1">
                <.state_breakdown stats={@total} statuses_order={@statuses_order} />
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  defp state_breakdown(assigns) do
    ~H"""
    <div class="flex flex-wrap gap-x-3 gap-y-1">
      <%= for status <- @statuses_order, Map.get(@stats.durations, status, 0) > 0 do %>
        <span class="inline-flex items-center gap-1 font-mono">
          <span class="inline-block w-2.5 h-2.5 rounded-sm" style={"background:#{status_color(status)}"}></span>
          <span class="text-gray-500">{status_label(status)}</span>
          <span>{format_duration_ms(Map.get(@stats.durations, status, 0))}</span>
          <span class="text-gray-400">· {format_duration_ms(avg_duration(@stats, status))}</span>
        </span>
      <% end %>
    </div>
    """
  end

  defp timeline_rows(assigns) do
    ~H"""
    <div class="flex flex-col gap-1">
      <%= for device <- @devices do %>
        <div class="flex items-center gap-3">
          <div class="w-32 shrink-0">
            <%= if @interactive do %>
              <button
                type="button"
                phx-click="toggle_sensor"
                phx-value-device_id={device.device_id}
                class={[
                  "btn btn-sm font-mono w-full justify-start",
                  sensor_status_class(@statuses[device.device_id])
                ]}
                title={"Sensor #{device_letter(device.device_id)} (#{device.port}) — #{status_label(@statuses[device.device_id])} — click to toggle"}
              >
                {device_letter(device.device_id)}
                <span class="text-xs ml-1 opacity-80 truncate">
                  {status_label(@statuses[device.device_id])}
                </span>
              </button>
            <% else %>
              <div class={[
                "btn btn-sm font-mono w-full justify-start cursor-default pointer-events-none",
                sensor_status_class(@statuses[device.device_id])
              ]}>
                {device_letter(device.device_id)}
                <span class="text-xs ml-1 opacity-80 truncate">
                  {status_label(@statuses[device.device_id])}
                </span>
              </div>
            <% end %>
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
    """
  end

  defp timeline_ruler(assigns) do
    ~H"""
    <div class="ml-[8.75rem] mt-1">
      <svg
        width="100%"
        height="14"
        viewBox={"0 0 #{@vb_width} 14"}
        preserveAspectRatio="none"
        xmlns="http://www.w3.org/2000/svg"
        style="display:block"
      >
        <%= for s <- [10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 110, 120] do %>
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
    """
  end

  defp snapshot_section(assigns) do
    ~H"""
    <div class="mt-6 pt-4 border-t border-dashed border-gray-300">
      <div class="flex items-center gap-2 mb-2 ml-[8.75rem]">
        <span class="font-mono text-xs text-amber-700 font-semibold">📸 <%= @snapshot.id %></span>
        <span class="text-xs text-gray-400"><%= @snapshot.captured_label %></span>
        <button
          type="button"
          id={"copy-dump-#{@snapshot.id}"}
          phx-hook="CopyDump"
          data-dump={@snapshot.dump_json}
          data-snap-id={@snapshot.id}
          class="btn btn-xs btn-outline"
          title="Generate full 1-hour JSON dump for this snapshot, log it, and copy to clipboard"
        >
          📋 Copy Dump
        </button>
        <button
          type="button"
          phx-click="delete_snapshot"
          phx-value-id={@snapshot.id}
          class="btn btn-xs btn-ghost text-red-400 hover:text-red-600"
          title="Delete this snapshot"
        >
          × Delete
        </button>
      </div>
      <.timeline_rows
        devices={@devices}
        statuses={@snapshot.statuses}
        histories={@snapshot.histories}
        now_ms={@snapshot.now_ms}
        vb_width={@vb_width}
        vb_height={@vb_height}
        units_per_second={@units_per_second}
        window_ms={@window_ms}
        interactive={false}
      />
      <.timeline_ruler
        now_ms={@snapshot.now_ms}
        vb_width={@vb_width}
        units_per_second={@units_per_second}
        window_ms={@window_ms}
      />
    </div>
    """
  end

  ## Private helpers

  defp generate_snap_id do
    Calendar.strftime(DateTime.utc_now(), "snap-%Y%m%dT%H%M%SZ")
  end

  defp generate_dump_id do
    Calendar.strftime(DateTime.utc_now(), "dump-%Y%m%dT%H%M%SZ")
  end

  defp generate_dump_json(dump_id) do
    history = if Radar.enabled?(), do: Radar.get_history(), else: %{}
    generate_dump_json(dump_id, history)
  end

  defp generate_dump_json(dump_id, history) do
    sensors =
      Map.new(history, fn {device_id, entries} ->
        letter = device_letter(device_id)
        pairs = entries |> Enum.reverse() |> Enum.map(fn {t, s} -> [t, Atom.to_string(s)] end)
        {letter, pairs}
      end)

    Jason.encode!(%{"captured_at" => DateTime.to_iso8601(DateTime.utc_now()), "dump_id" => dump_id, "sensors" => sensors})
  end

  # Returns [{x, major?}] for wall-clock-aligned 1-second divider lines.
  # x is in SVG units. Lines where the underlying second is divisible by 10
  # are major (thick). Because x is derived from now_ms every tick, the lines
  # shift rightward continuously, making elapsed time visible.
  defp ruler_lines(now_ms, units_per_second, vb_width) do
    units_per_ms = units_per_second / 1_000.0
    sec_offset = rem(now_ms, 1_000) * units_per_ms
    sec_index = rem(div(now_ms, 1_000), 10)

    for i <- 0..130,
        x = sec_offset + i * units_per_second,
        x > 0.0,
        x < vb_width do
      {x, rem(i, 10) == sec_index}
    end
  end

  # Converts a newest-first history list into [{x, width, status}] SVG segments.
  # x=0 is NOW (left edge), x=@vb_width is window_ms ago (right edge).
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

    rev_segs =
      if last_x > 0 do
        [{0, last_x, last_status} | rev_segs]
      else
        rev_segs
      end

    Enum.reverse(rev_segs)
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

  # Statuses in display order for the per-state breakdown. Mirrors status_legend/0.
  defp stats_statuses_order do
    [:working, :probing, :initializing, :stale, :unavailable, :resetting, :inactive]
  end

  defp empty_stats do
    %{total_ms: 0, durations: %{}, entries: %{}, dropouts: 0, retries: 0, current_status: :inactive}
  end

  defp sensor_stat(stats, device_id), do: Map.get(stats, device_id, empty_stats())

  defp aggregate_stats(devices, stats) do
    Enum.reduce(devices, empty_stats(), fn device, acc ->
      s = sensor_stat(stats, device.device_id)

      %{
        acc
        | total_ms: acc.total_ms + s.total_ms,
          dropouts: acc.dropouts + s.dropouts,
          retries: acc.retries + s.retries,
          durations: Map.merge(acc.durations, s.durations, fn _k, a, b -> a + b end),
          entries: Map.merge(acc.entries, s.entries, fn _k, a, b -> a + b end)
      }
    end)
  end

  defp working_pct(%{total_ms: 0}), do: 0

  defp working_pct(%{durations: durations, total_ms: total_ms}) do
    round(Map.get(durations, :working, 0) / total_ms * 100)
  end

  defp avg_duration(%{durations: durations, entries: entries}, status) do
    count = Map.get(entries, status, 0)
    if count > 0, do: div(Map.get(durations, status, 0), count), else: 0
  end

  defp format_duration_ms(ms) when ms < 1_000, do: "#{ms}ms"

  defp format_duration_ms(ms) do
    total_seconds = div(ms, 1_000)
    hours = div(total_seconds, 3_600)
    minutes = total_seconds |> rem(3_600) |> div(60)
    seconds = rem(total_seconds, 60)

    cond do
      hours > 0 -> "#{hours}h #{pad2(minutes)}m #{pad2(seconds)}s"
      minutes > 0 -> "#{minutes}m #{pad2(seconds)}s"
      true -> "#{seconds}s"
    end
  end

  defp pad2(n), do: String.pad_leading(Integer.to_string(n), 2, "0")

  defp status_color(status), do: Map.get(@status_colors, status, "#d1d5db")

  defp status_label(:inactive), do: "Inactive"
  defp status_label(:unavailable), do: "Unavailable"
  defp status_label(:initializing), do: "Initializing"
  defp status_label(:probing), do: "Probing"
  defp status_label(:working), do: "Working"
  defp status_label(:stale), do: "No Data"
  defp status_label(:resetting), do: "Resetting"
  defp status_label(_), do: "Unknown"

  defp status_legend do
    [
      {:working, @status_colors.working},
      {:probing, @status_colors.probing},
      {:initializing, @status_colors.initializing},
      {:stale, @status_colors.stale},
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

  defp sensor_status_class(:probing),
    do: "bg-cyan-500 text-white border-cyan-600"

  defp sensor_status_class(:working),
    do: "bg-green-500 text-white border-green-600"

  defp sensor_status_class(:stale),
    do: "bg-orange-500 text-white border-orange-600"

  defp sensor_status_class(:resetting),
    do: "bg-gray-900 text-white border-gray-800"

  defp sensor_status_class(_), do: sensor_status_class(:unavailable)
end
