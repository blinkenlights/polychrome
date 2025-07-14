defmodule OctopusWeb.FirmwareInfoLive do
  use OctopusWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      :timer.send_interval(1000, :update)
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
      <div class="bg-white shadow rounded-lg p-4">
        <table class="min-w-full table-auto border-collapse border border-gray-300 text-center">
          <thead>
            <tr class="bg-gray-100">
              <th class="border py-1">Panel Index</th>
              <th class="border py-1">Hostname</th>
              <th class="border py-1">MAC</th>
              <th class="border py-1">IPv4</th>
              <th class="border py-1">Build Time</th>
              <th class="border py-1">Config Phash</th>
              <th class="border py-1">FPS</th>
              <th class="border py-1">Packets/s</th>
              <th class="border py-1">Proximity/s</th>
              <th class="border py-1">Uptime</th>
              <th class="border py-1">Last Seen</th>
            </tr>
          </thead>
          <tbody>
            <%= for {mac, meta} <- @firmware_stats do %>
              <tr>
                <td class="border py-1">{meta.firmware_info.panel_index}</td>
                <td class="border py-1">{meta.firmware_info.hostname}</td>
                <td class="border py-1">{mac}</td>
                <td class="border py-1">{meta.firmware_info.ipv4}</td>
                <td class="border py-1">
                  {format_build_time(meta.firmware_info.build_time, @current_time)}
                </td>
                <td class="border py-1">{meta.firmware_info.config_phash}</td>
                <td class="border py-1">{meta.firmware_info.frames_per_second}</td>
                <td class="border py-1">{meta.firmware_info.packets_per_second}</td>
                <td class="border py-1">{meta.firmware_info.proximity_readings_per_second}</td>
                <td class="border py-1">{format_uptime(meta.firmware_info.uptime)}</td>
                <td class="border py-1">{time_ago(meta.last_seen, @current_time)}</td>
              </tr>
            <% end %>
          </tbody>
        </table>
        <%= if length(@firmware_stats) == 0 do %>
          <p class="text-gray-600 mt-4">No firmware devices found.</p>
        <% end %>
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
      seconds < 3600 -> "#{div(seconds, 60)}m"
      seconds < 86400 -> "#{div(seconds, 3600)}h"
      true -> "#{div(seconds, 86400)}d"
    end
  end
end
