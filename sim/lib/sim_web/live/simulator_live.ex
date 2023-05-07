defmodule SimWeb.SimulatorLive do
  use SimWeb, :live_view
  use SimWeb.PixelsComponent

  alias Sim.Layout.Mildenberg
  alias Sim.Pixels

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Sim.Pixels.subscribe()
    end

    layout = Mildenberg.layout()
    config = Pixels.config()
    pixels = Pixels.pixels()

    socket =
      socket
      |> assign(pixel_layout: layout)
      |> push_layout(layout)
      |> push_config(config)
      |> push_pixels(pixels)

    {:ok, socket, temporary_assigns: [pixel_layout: %{}]}
  end

  def render(assigns) do
    ~H"""
    <div class="flex w-full h-full justify-center bg-black">
      <.pixels id="pixels" pixel_layout={@pixel_layout} />
    </div>
    """
  end

  def handle_info({:pixels, pixels}, socket) do
    {:noreply, socket |> push_pixels(pixels)}
  end

  def handle_info({:config, config}, socket) do
    {:noreply, socket |> push_config(config)}
  end
end
