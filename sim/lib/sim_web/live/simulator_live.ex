defmodule SimWeb.SimulatorLive do
  use SimWeb, :live_view
  use SimWeb.PixelsComponent

  alias Sim.Layout.Mildenberg
  alias Sim.Pixels

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Sim.Pixels.subscribe()
    end

    pixels = Pixels.encoded_pixels()
    layout = Mildenberg.layout()

    {:ok,
     socket
     |> assign(pixel_layout: layout)
     |> push_layout(layout)
     |> push_pixels(pixels), temporary_assigns: [pixel_layout: %{}]}
  end

  def render(assigns) do
    ~H"""
    <div class="flex w-full h-full justify-center bg-black">
      <.pixels id="pixels" pixel_layout={@pixel_layout} />
    </div>
    """
  end

  def handle_info({:pixels, pixels, _max_value}, socket) do
    {:noreply, socket |> push_pixels(pixels)}
  end
end
