defmodule OctopusWeb.PixelsComponent do
  @moduledoc """
  A component for displaying pixels using a Phoenix Hook.

  ## Examples

      defmodule ExampleWeb.ExampleLive do
        alias OctopusWeb.PixelsComponent

        import PixelsComponent, only: [pixels: 1]

        def mount(_params, _session, socket) do
          pixel_layout = Octopus.Layout.Mildenberg.layout()
          socket =
            socket
            |> PixelsComponent.mount(socket)
            |> assign(pixel_layout: pixel_layout)
          {:ok, socket, temporary_assigns: [pixel_layout: nil]}
        end

        def render(assigns) do
          ~H\"""
            <.pixels id="pixels" pixel_layout={@pixel_layout} />
          \"""
        end

        def handle_info({:mixer, {:frame, frame}}, socket) do
          {:noreply, socket |> PixelsComponent.push_frame(frame)}
        end

        def handle_info({:mixer, {:config, config}}, socket) do
          {:noreply, socket |> PixelsComponent.push_config(config)}
        end
      end

  ## Multiple pixel components in one liveview

  The component supports multiple instances in the same live view
  which can be updated individually or all at one.
  `push_frame/3`, `push_config/3` and `push_layout/3` take an optional
  third `id` parameter which refers to the id given to the component
  in the heex template.

      defmodule ExampleWeb.ExampleLive do
        alias OctopusWeb.PixelsComponent

        import PixelsComponent, only: [pixels: 1]

        def mount(socket) do
          layout = Octopus.Layout.Mildenberg.layout()
          socket =
            socket
            |> PixelsComponent.mount(socket)
            |> push_frame(%Frame{}, "foo")
            |> push_frame(%Frame{}, "bar")
            # No ID given here, the config will be sent to both components
            |> push_config(%Config{})
            |> assign(pixel_layout: pixel_layout)
            {:ok, socket, temporary_assigns: [pixel_layout: nil]}
        end

        def render(assigns) do
          ~\"""
            <.pixels id="foo" />
            <.pixels id="bar" />
          \"""
        end
      end
  """

  use Phoenix.Component

  import Phoenix.LiveView, only: [push_event: 3, connected?: 1]

  alias Octopus.ColorPalette
  alias Octopus.Mixer
  alias Octopus.Protobuf.{Config, Frame}

  @default_config %Config{
    easing_interval_ms: 1000,
    easing_mode: :LINEAR,
    show_test_frame: false
  }

  attr(:id, :string, required: true)
  attr(:pixel_layout, Octopus.Layout, required: true)

  @doc """
  Renders the pixels on a canvas.
  """
  def pixels(assigns) do
    ~H"""
    <canvas
      id={@id}
      phx-hook="Pixels"
      class="w-full h-full bg-contain bg-no-repeat bg-center"
      style={"background-image: url(#{@pixel_layout.background_image});"}
    />
    """
  end

  @doc """
  Sets up the layout, config, and pubsub subscribptions.

  Should be called in the `Phoenix.LiveView.mount/3` callback.
  """
  def setup(socket) do
    if connected?(socket) do
      Mixer.subscribe()

      layout = socket.assigns.pixel_layout
      config = @default_config

      frame = %Frame{
        data: List.duplicate(0, layout.width * layout.height),
        palette: ColorPalette.load("pico-8")
      }

      socket
      |> push_layout(layout)
      |> push_config(config)
      |> push_frame(frame)
    else
      socket
    end
  end

  @doc """
  Pushes a layout to the client using push_event/3.
  """
  def push_layout(socket, layout, id \\ "*") do
    push_event(socket, "layout:#{id}", %{layout: layout})
  end

  @doc """
  Pushes a frame to the client.
  """
  def push_frame(socket, frame, id \\ "*") do
    push_event(socket, "frame:#{id}", %{frame: frame})
  end

  @doc """
  Pushes a config to the client.
  """
  def push_config(socket, config, id \\ "*") do
    push_event(socket, "config:#{id}", %{config: config})
  end

  @doc """
  Pushes a pixel offset to the client.

  Used to "paginate" windows when using a layout which is
  zoomed in on a subset of the pixels.
  """
  def push_pixel_offset(socket, offset, id \\ "*") do
    push_event(socket, "pixel_offset:#{id}", %{offset: offset})
  end
end
