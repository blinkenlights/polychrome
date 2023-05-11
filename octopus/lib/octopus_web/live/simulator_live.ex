defmodule OctopusWeb.SimulatorLive do
  use OctopusWeb, :live_view
  use OctopusWeb.PixelsComponent

  alias Octopus.ColorPalette
  alias Octopus.Layout.Mildenberg
  alias Octopus.Protobuf.Config
  alias Octopus.Protobuf.Frame

  @default_config %Config{
    easing_interval_ms: 1000,
    easing_mode: :LINEAR,
    show_test_frame: false
  }

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Octopus.Mixer.subscribe()
    end

    layout = Mildenberg.layout()
    config = @default_config

    frame = %Frame{
      data: List.duplicate(0, layout.width * layout.height),
      palette: ColorPalette.from_file("pico-8")
    }

    socket =
      socket
      |> assign(pixel_layout: layout)
      |> push_layout(layout)
      |> push_config(config)
      |> push_frame(frame)

    {:ok, socket, temporary_assigns: [pixel_layout: %{}]}
  end

  def render(assigns) do
    ~H"""
    <div class="flex w-full h-full justify-center bg-black">
      <.pixels id="pixels" pixel_layout={@pixel_layout} />
    </div>
    """
  end

  def handle_info({:frame, frame}, socket) do
    {:noreply, socket |> push_frame(frame)}
  end

  def handle_info({:config, config}, socket) do
    {:noreply, socket |> push_config(config)}
  end
end
