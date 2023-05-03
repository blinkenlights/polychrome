defmodule SimWeb.SimulatorLive do
  use SimWeb, :live_view

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
     |> assign(background_image: layout.background_image, pixel_image: layout.pixel_image)
     |> push_event("layout", %{layout: layout})
     |> push_event("pixels", %{pixels: pixels})}
  end

  def render(assigns) do
    ~H"""
    <div class="flex w-full h-full justify-center bg-black">
      <canvas
        id="pixels"
        phx-hook="Pixels"
        class="w-full h-full bg-contain bg-no-repeat bg-center"
        data-pixel-image-url={@pixel_image}
        style={"background-image: url(#{@background_image});"}
      >
      </canvas>
    </div>
    """
  end

  def handle_info({:pixels, pixels, max_value}, socket) do
    {:noreply, push_event(socket, "pixels", %{pixels: pixels, max_value: max_value})}
  end
end
