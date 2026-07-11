defmodule OctopusWeb.TopBarComponent do
  @moduledoc false
  use OctopusWeb, :html

  attr :current_path, :string, default: "/"

  def top_bar(assigns) do
    assigns = assign(assigns, :foyer?, assigns.current_path == "/")

    ~H"""
    <nav
      id="top-bar"
      phx-hook="TopBar"
      data-foyer={to_string(@foyer?)}
      data-show-sim-layout={to_string(@foyer?)}
      class="fixed top-0 inset-x-0 z-[60] h-10 flex items-center gap-4 px-3 sm:px-4 border-b border-base-300 bg-base-100/95 backdrop-blur-sm"
      style="--top-bar-height: 2.5rem"
    >
      <div class="flex items-center gap-1 sm:gap-2 min-w-0">
        <%= for {path, label} <- nav_links() do %>
          <.nav_link path={path} label={label} current_path={@current_path} />
        <% end %>
      </div>

      <div class="ml-auto flex items-center gap-1.5 shrink-0">
        <button
          :if={@foyer?}
          id="top-bar-sim-layout"
          type="button"
          data-action="toggle-sim-layout"
          class="hidden min-[700px]:inline-flex btn btn-ghost btn-xs btn-square w-8 h-8"
          aria-label="Toggle sim layout"
          title="Toggle sim layout"
        >
          <span data-sim-layout-icon>↑</span>
        </button>
        <button
          id="top-bar-theme"
          type="button"
          data-action="toggle-theme"
          class="btn btn-ghost btn-xs btn-square w-8 h-8"
          aria-label="Toggle theme"
          title="Toggle theme"
        >
          <span data-theme-icon>☾</span>
        </button>
      </div>
    </nav>
    <div class="h-10 shrink-0" aria-hidden="true" />
    """
  end

  attr :path, :string, required: true
  attr :label, :string, required: true
  attr :current_path, :string, required: true

  defp nav_link(assigns) do
    active? = nav_active?(assigns.path, assigns.current_path)

    assigns = assign(assigns, :active?, active?)

    ~H"""
    <.link
      navigate={@path}
      class={[
        "px-2 py-1 rounded-md text-sm font-medium whitespace-nowrap transition-colors",
        @active? && "bg-base-200 text-base-content",
        !@active? && "text-base-content/70 hover:text-base-content hover:bg-base-200/60"
      ]}
    >
      {@label}
    </.link>
    """
  end

  defp nav_active?(path, current_path) when is_binary(path) and is_binary(current_path) do
    current_path == path
  end

  defp nav_active?(_, _), do: false

  defp nav_links do
    [
      {"/", "Foyer"},
      {"/sim3daframe", "Aframe"},
      {"/radar", "Radar"},
      {"/radar/debug", "Radar Debug"}
    ]
  end
end
