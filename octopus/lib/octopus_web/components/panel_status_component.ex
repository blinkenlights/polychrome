defmodule OctopusWeb.PanelStatusComponent do
  @moduledoc """
  Compact row of per-panel status dots for simulator views.
  """

  use Phoenix.Component

  attr :panel_statuses, :list, required: true
  attr :enabled, :boolean, default: false

  def panel_status_boxes(assigns) do
    ~H"""
    <div :if={@enabled} class="flex flex-wrap gap-1.5 items-center">
      <div
        :for={entry <- @panel_statuses}
        class={[
          "min-w-[1.75rem] h-7 px-1.5 flex items-center justify-center rounded",
          "text-xs font-mono font-bold text-white shadow-sm",
          status_box_class(entry.status)
        ]}
        title={status_title(entry)}
      >
        {entry.panel}
      </div>
    </div>
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

  defp status_box_class(:online), do: "bg-green-600"
  defp status_box_class(:stale), do: "bg-yellow-500 text-black"
  defp status_box_class(:offline), do: "bg-red-600"
  defp status_box_class(_), do: "bg-red-600"

  defp status_title(%{status: status, last_seen: last_seen}) when is_integer(last_seen) do
    "Panel #{status} (last seen #{last_seen}s epoch)"
  end

  defp status_title(%{status: status}), do: "Panel #{status}"
end
