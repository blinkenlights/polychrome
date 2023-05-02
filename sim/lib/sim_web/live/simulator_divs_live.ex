defmodule SimWeb.SimulatorDivsLive do
  use SimWeb, :live_view

  alias Sim.Layout

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      :timer.send_interval(100, self(), :tick)
    end

    pixel_layout = Sim.Layout.Mildenberg.layout()

    pixels =
      List.duplicate(false, length(pixel_layout.positions))
      |> Enum.with_index()
      |> Enum.map(fn {value, i} -> %{id: i, value: value} end)

    background_image = ~p"/images/mildenberg.jpg"

    {:ok,
     socket
     |> stream(:pixels, pixels, dom_id: &"p#{&1.id}")
     |> assign(internal_pixels: pixels)
     |> assign(pixel_layout: pixel_layout, background_image: background_image)}
  end

  @impl true
  def handle_info(:tick, socket) do
    pixels =
      socket.assigns.internal_pixels
      |> Enum.map(fn pixel ->
        %{pixel | value: !pixel.value}
      end)

    socket = assign(socket, internal_pixels: pixels)

    socket =
      Enum.reduce(pixels, socket, fn pixel, socket ->
        stream_insert(socket, :pixels, pixel, at: pixel.id)
      end)

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container mx-auto">
      <div class="grid justify-items-cente">
        <.display
          background_image={@background_image}
          pixel_layout={@pixel_layout}
          pixels={@streams.pixels}
        />
      </div>
    </div>
    """
  end

  attr :background_image, :string
  attr :pixel_layout, Layout
  attr :pixels, :any

  def display(assigns) do
    ~H"""
    <div id="pixels" class="pixels relative" phx-update="append">
      <style id="pixel-styles">
        <%= pixel_styles(@pixel_layout) %>
      </style>
      <img id="pixels-background" src={@background_image} class="relative aspect-auto" />

      <div
        :for={{dom_id, pixel} <- @pixels}
        id={dom_id}
        class={if pixel.value, do: "on", else: "off"}
      />
    </div>
    """
  end

  defp pixel_styles(%Sim.Layout{
         pixel_size: {pixel_width, pixel_height},
         positions: positions,
         image_size: {image_width, image_height}
       }) do
    pixel_width = Float.round(pixel_width / image_width * 100, 2)
    pixel_height = Float.round(pixel_height / image_height * 100, 2)

    positions
    |> Enum.with_index()
    |> Enum.map(fn {{x, y}, i} ->
      ~s"""
      .pixels div {
        position: absolute;
      }
      .pixels div.off {
        background-color: black;
      }
      .pixels div.on {
        background-color: orange;
      }
      .pixels div:nth-of-type(#{i + 1}) {
        left: #{x / image_width * 100}%;
        top: #{y / image_height * 100}%;
        width: #{pixel_width}%;
        height: #{pixel_height}%;
      }
      """
    end)
  end
end
