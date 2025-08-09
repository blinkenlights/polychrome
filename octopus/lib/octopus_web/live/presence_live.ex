defmodule OctopusWeb.PresenceLive do
  use OctopusWeb, :live_view

  alias Octopus.Presence
  alias Octopus.PubSub

  @presence "presence"

  def on_mount(:default, _params, _session, socket) do
    {:cont, socket}
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Presence.track(self(), @presence, :crypto.strong_rand_bytes(10), %{})
      Phoenix.PubSub.subscribe(PubSub, @presence)
    end

    online = Presence.list(@presence) |> Enum.count()
    {:ok, assign(socket, online: online)}
  end

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff", payload: _diff}, socket) do
    online = Presence.list(@presence) |> Enum.count()
    {:noreply, assign(socket, online: online)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      class="absolute top-0 left-0 p-2 z-50"
      title="Users online"
    >
      <div class="badge badge-success gap-2">
        <div class="w-2 h-2 rounded-full bg-success-content animate-pulse"></div>
        <span class="font-mono"><%= @online %></span>
      </div>
    </div>
    """
  end
end
