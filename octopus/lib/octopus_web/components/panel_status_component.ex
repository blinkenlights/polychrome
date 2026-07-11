defmodule OctopusWeb.PanelStatusComponent do
  @moduledoc """
  Compact row of per-panel status dots for simulator views.
  """

  use Phoenix.Component

  attr :panel_statuses, :list, required: true
  attr :visible, :boolean, default: false
  attr :sending_enabled, :boolean, default: false
  attr :current_time, :integer, default: 0

  def panel_status_boxes(assigns) do
    ~H"""
    <div :if={@visible} class="flex flex-wrap gap-1.5 items-center">
      <button
        id="panel-sending-toggle"
        type="button"
        phx-click="toggle-panel-sending"
        class={[
          "h-7 w-7 flex items-center justify-center rounded shadow-sm",
          @sending_enabled && "bg-green-600 text-white",
          !@sending_enabled && "bg-gray-600 text-gray-300"
        ]}
        title={sending_toggle_title(@sending_enabled)}
        aria-pressed={to_string(@sending_enabled)}
        aria-label="Toggle panel output"
      >
        <.matrix_icon />
      </button>
      <div
        :for={entry <- @panel_statuses}
        id={"panel-status-#{entry.panel}"}
        phx-hook=".PanelFirmwareOverlay"
        class="relative"
      >
        <button
          type="button"
          data-panel-trigger
          class={[
            "min-w-[1.75rem] h-7 px-1.5 flex items-center justify-center rounded",
            "text-xs font-mono font-bold shadow-sm cursor-default",
            panel_box_class(@sending_enabled, entry.status)
          ]}
        >
          {entry.panel}
        </button>
        <div
          data-overlay
          class="hidden absolute left-0 top-full mt-1 z-50 w-56 rounded-lg border border-base-300 bg-base-100 p-3 text-left text-xs shadow-xl pointer-events-none"
        >
          <.firmware_overlay entry={entry} current_time={@current_time} />
        </div>
      </div>
    </div>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".PanelFirmwareOverlay">
      export default {
        mounted() {
          this.overlay = this.el.querySelector("[data-overlay]")
          this.hasHover = window.matchMedia("(hover: hover)").matches

          if (this.hasHover) {
            this.el.addEventListener("mouseenter", () => this.show())
            this.el.addEventListener("mouseleave", () => this.hide())
          } else {
            this.onTriggerClick = (e) => {
              e.stopPropagation()
              this.toggle()
            }
            this.onDocClick = () => this.hide()
            this.el.querySelector("[data-panel-trigger]").addEventListener("click", this.onTriggerClick)
            document.addEventListener("click", this.onDocClick)
          }
        },
        destroyed() {
          if (this.onDocClick) document.removeEventListener("click", this.onDocClick)
        },
        show() {
          this.overlay?.classList.remove("hidden")
        },
        hide() {
          this.overlay?.classList.add("hidden")
        },
        toggle() {
          this.overlay?.classList.toggle("hidden")
        }
      }
    </script>
    """
  end

  defp matrix_icon(assigns) do
    ~H"""
    <svg viewBox="0 0 16 16" class="w-4 h-4" aria-hidden="true">
      <rect x="1" y="1" width="4" height="4" rx="0.5" fill="currentColor" />
      <rect x="6" y="1" width="4" height="4" rx="0.5" fill="currentColor" />
      <rect x="11" y="1" width="4" height="4" rx="0.5" fill="currentColor" />
      <rect x="1" y="6" width="4" height="4" rx="0.5" fill="currentColor" />
      <rect x="6" y="6" width="4" height="4" rx="0.5" fill="currentColor" />
      <rect x="11" y="6" width="4" height="4" rx="0.5" fill="currentColor" />
      <rect x="1" y="11" width="4" height="4" rx="0.5" fill="currentColor" />
      <rect x="6" y="11" width="4" height="4" rx="0.5" fill="currentColor" />
      <rect x="11" y="11" width="4" height="4" rx="0.5" fill="currentColor" />
    </svg>
    """
  end

  attr :entry, :map, required: true
  attr :current_time, :integer, required: true

  defp firmware_overlay(assigns) do
    ~H"""
    <p class="font-semibold text-sm mb-2">
      Panel {@entry.panel}
      <span class={["ml-1 font-normal", status_text_class(@entry.status)]}>
        {status_label(@entry.status)}
      </span>
    </p>
    <dl class="grid grid-cols-[auto_1fr] gap-x-2 gap-y-1 font-mono">
      <dt class="text-base-content/60">Controller</dt>
      <dd>{@entry.controller_id}</dd>
      <%= if @entry.firmware_info do %>
        <dt class="text-base-content/60">Hostname</dt>
        <dd class="truncate">{@entry.firmware_info.hostname}</dd>
        <dt class="text-base-content/60">MAC</dt>
        <dd class="truncate">{@entry.firmware_info.mac}</dd>
        <dt class="text-base-content/60">IPv4</dt>
        <dd>{@entry.firmware_info.ipv4}</dd>
        <dt class="text-base-content/60">FW index</dt>
        <dd>{@entry.firmware_info.panel_index}</dd>
        <dt class="text-base-content/60">Version</dt>
        <dd>{format_build_time(@entry.firmware_info.build_time, @current_time)}</dd>
        <dt class="text-base-content/60">FPS</dt>
        <dd>{@entry.firmware_info.frames_per_second}</dd>
        <dt class="text-base-content/60">Pkts/s</dt>
        <dd>{@entry.firmware_info.packets_per_second}</dd>
        <dt class="text-base-content/60">Prox/s</dt>
        <dd>{@entry.firmware_info.proximity_readings_per_second}</dd>
        <dt class="text-base-content/60">Uptime</dt>
        <dd>{format_uptime(@entry.firmware_info.uptime)}</dd>
        <dt class="text-base-content/60">Config</dt>
        <dd>{@entry.firmware_info.config_phash}</dd>
        <dt class="text-base-content/60">Last seen</dt>
        <dd>{time_ago(@entry.last_seen, @current_time)}</dd>
      <% else %>
        <dt class="text-base-content/60">Status</dt>
        <dd class="col-span-1">No firmware heartbeat</dd>
      <% end %>
    </dl>
    """
  end

  attr :panel_statuses, :list, required: true
  attr :enabled, :boolean, default: false

  def panel_status_bar(assigns) do
    ~H"""
    <div :if={@enabled} class="flex flex-wrap gap-2 items-center">
      <div :for={entry <- @panel_statuses} class="flex items-center gap-1 text-xs">
        <span class="font-mono tabular-nums">{entry.panel}</span>
        <.status_dot status={entry.status} title={status_title(entry)} />
      </div>
    </div>
    """
  end

  attr :enabled, :boolean, default: false
  attr :panel_statuses, :list, required: true

  def inline_status_dots(assigns) do
    ~H"""
    <span :if={@enabled} class="inline-flex items-center gap-1">
      <.status_dot
        :for={entry <- @panel_statuses}
        status={entry.status}
        title={status_title(entry)}
      />
    </span>
    """
  end

  attr :status, :atom, required: true
  attr :title, :string, default: nil
  attr :class, :string, default: nil

  defp status_dot(assigns) do
    ~H"""
    <span
      class={[
        "inline-block w-2.5 h-2.5 rounded-full shrink-0",
        status_color_class(@status),
        @class
      ]}
      title={@title}
    />
    """
  end

  defp status_color_class(:online), do: "bg-green-500"
  defp status_color_class(:stale), do: "bg-yellow-500"
  defp status_color_class(:offline), do: "bg-red-500"
  defp status_color_class(_), do: "bg-red-500"

  defp panel_box_class(false, _status), do: "bg-gray-500 text-gray-100 border border-gray-400"
  defp panel_box_class(true, status), do: status_box_class(status) <> " text-white"

  defp sending_toggle_title(true), do: "Panel output on — click to stop sending"
  defp sending_toggle_title(false), do: "Panel output off — click to start sending"

  defp status_box_class(:online), do: "bg-green-600"
  defp status_box_class(:stale), do: "bg-yellow-500 text-black"
  defp status_box_class(:offline), do: "bg-red-600"
  defp status_box_class(_), do: "bg-red-600"

  defp status_text_class(:online), do: "text-green-600"
  defp status_text_class(:stale), do: "text-yellow-600"
  defp status_text_class(:offline), do: "text-red-600"
  defp status_text_class(_), do: "text-red-600"

  defp status_label(:online), do: "online"
  defp status_label(:stale), do: "stale"
  defp status_label(:offline), do: "offline"
  defp status_label(_), do: "unknown"

  defp status_title(%{status: status, last_seen: last_seen}) when is_integer(last_seen) do
    "Panel #{status} (last seen #{last_seen}s epoch)"
  end

  defp status_title(%{status: status}), do: "Panel #{status}"

  defp format_build_time(build_time, current_time) when is_binary(build_time) do
    case Integer.parse(build_time) do
      {timestamp, ""} -> time_ago(timestamp, current_time)
      _ -> build_time
    end
  end

  defp format_build_time(_, _), do: "-"

  defp format_uptime(milliseconds) when is_integer(milliseconds) do
    seconds = div(milliseconds, 1000)
    format_duration(seconds)
  end

  defp format_uptime(_), do: "-"

  defp format_duration(seconds) do
    cond do
      seconds < 60 -> "#{seconds}s"
      seconds < 3_600 -> "#{div(seconds, 60)}m"
      seconds < 86_400 -> "#{div(seconds, 3_600)}h"
      true -> "#{div(seconds, 86_400)}d"
    end
  end

  defp time_ago(nil, _current_time), do: "-"

  defp time_ago(timestamp, current_time) do
    diff = current_time - timestamp
    format_duration(diff) <> " ago"
  end
end
