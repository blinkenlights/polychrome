defmodule OctopusWeb.SimulatorLive do
  use OctopusWeb, :live_view

  alias Octopus.Layout.Mildenberg
  alias OctopusWeb.PixelsComponent

  import PixelsComponent, only: [pixels: 1]

  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(pixel_layout: Mildenberg.layout())
      |> PixelsComponent.setup()

    {:ok, socket, temporary_assigns: [pixel_layout: nil]}
  end

  def render(assigns) do
    ~H"""
    <div class="flex w-full h-full justify-center bg-black">
      <.pixels id="pixels" pixel_layout={@pixel_layout} />
    </div>
    """
  end

  def handle_info({:mixer, {:frame, frame}}, socket) do
    {:noreply, socket |> PixelsComponent.push_frame(frame)}
  end

  def handle_info({:mixer, {:config, config}}, socket) do
    {:noreply, socket |> PixelsComponent.push_config(config)}
  end

  # Ignore other mixer events. We are only interested in the mixer output.
  def handle_info({:mixer, _}, socket) do
    {:noreply, socket}
  end
end
