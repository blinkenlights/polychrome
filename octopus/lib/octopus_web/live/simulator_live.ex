defmodule OctopusWeb.SimulatorLive do
  use OctopusWeb, :live_view
  use OctopusWeb.PixelsComponent

  alias OctopusWeb.PixelsComponent

  def mount(_params, _session, socket) do
    socket = PixelsComponent.mount(socket)
    {:ok, socket, temporary_assigns: PixelsComponent.temporary_assigns()}
  end

  def render(assigns) do
    ~H"""
    <div class="flex w-full h-full justify-center bg-black">
      <.pixels id="pixels" pixel_layout={@pixel_layout} />
    </div>
    """
  end

  def handle_info({:mixer, {:frame, frame}}, socket) do
    {:noreply, socket |> push_frame(frame)}
  end

  def handle_info({:mixer, {:config, config}}, socket) do
    {:noreply, socket |> push_config(config)}
  end

  # Ignore other mixer events. We are only interested in the mixer output.
  def handle_info({:mixer, _}, socket) do
    {:noreply, socket}
  end
end
