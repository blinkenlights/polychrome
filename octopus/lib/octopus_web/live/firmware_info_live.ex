defmodule OctopusWeb.FirmwareInfoLive do
  use OctopusWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      :timer.send_interval(1_000, :update)
      send(self(), :update)
    end

    {:ok, assign(socket, firmware_stats: [], current_time: 0)}
  end

  @impl true
  def handle_info(:update, socket) do
    firmware_stats =
      Octopus.Broadcaster.firmware_stats()
      |> Enum.sort_by(fn {_mac, meta} -> meta.firmware_info.panel_index end)

    socket =
      socket
      |> assign(:firmware_stats, firmware_stats)
      |> assign(:current_time, System.os_time(:second))

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container mx-auto p-4">
      <div class="card bg-base-100 shadow-lg">
        <div class="card-body">
          <h1 class="card-title text-2xl mb-4">Firmware Information</h1>
          <div class="overflow-x-auto">
            <table class="table table-zebra w-full text-center">
              <thead>
                <tr>
                  <th>Panel Index</th>
                  <th>Hostname</th>
                  <th>MAC</th>
                  <th>IPv4</th>
                  <th>Build Time</th>
                  <th>Config Phash</th>
                  <th>FPS</th>
                  <th>Packets/s</th>
                  <th>Proximity/s</th>
                  <th>Uptime</th>
                  <th>Last Seen</th>
                </tr>
              </thead>
              <tbody>
                <%= for {mac, meta} <- @firmware_stats do %>
                  <tr>
                    <td>{meta.firmware_info.panel_index}</td>
                    <td>{meta.firmware_info.hostname}</td>
                    <td class="font-mono text-sm">{mac}</td>
                    <td class="font-mono text-sm">{meta.firmware_info.ipv4}</td>
                    <td>
                      {format_build_time(meta.firmware_info.build_time, @current_time)}
                    </td>
                    <td class="font-mono text-xs">{meta.firmware_info.config_phash}</td>
                    <td>{meta.firmware_info.frames_per_second}</td>
                    <td>{meta.firmware_info.packets_per_second}</td>
                    <td>{meta.firmware_info.proximity_readings_per_second}</td>
                    <td>{format_uptime(meta.firmware_info.uptime)}</td>
                    <td>{time_ago(meta.last_seen, @current_time)}</td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
          <%= if length(@firmware_stats) == 0 do %>
            <div class="alert alert-info mt-4">
              <svg
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 24 24"
                class="stroke-current shrink-0 w-6 h-6"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
                >
                </path>
              </svg>
              <span>No firmware devices found.</span>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp time_ago(nil, _current_time), do: "-"

  defp time_ago(timestamp, current_time) do
    diff = current_time - timestamp
    format_duration(diff) <> " ago"
  end

  defp format_build_time(build_time, current_time) when is_binary(build_time) do
    case Integer.parse(build_time) do
      {timestamp, _} -> time_ago(timestamp, current_time)
      :error -> build_time
    end
  end

  defp format_uptime(milliseconds) when is_integer(milliseconds) do
    seconds = div(milliseconds, 1000)
    format_duration(seconds)
  end

  defp format_duration(seconds) do
    cond do
      seconds < 60 -> "#{seconds}s"
      seconds < 3_600 -> "#{div(seconds, 60)}m"
      seconds < 86_400 -> "#{div(seconds, 3_600)}h"
      true -> "#{div(seconds, 86_400)}d"
    end
  end
end
