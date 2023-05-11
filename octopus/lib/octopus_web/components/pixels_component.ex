defmodule OctopusWeb.PixelsComponent do
  @moduledoc """
  A component for displaying pixels.

  ## Examples

      defmodule ExampleWeb.ExampleLive do
        use OctopusWeb.PixelsComponent

        def mount(_params, _session, socket) do
          socket = PixelsComponent.mount(socket)
          {:ok, socket, temporary_assigns: PixelsComponent.temporary_assigns()}
        end

        def render(assigns) do
          ~H\"""
            <.pixels id="pixels" pixel_layout={@pixel_layout} />
          \"""
        end

        def handle_info({:mixer, {:frame, frame}}, socket) do
          {:noreply, socket |> push_frame(frame)}
        end

        def handle_info({:mixer, {:config, config}}, socket) do
          {:noreply, socket |> push_config(config)}
        end
      end
  """

  use Phoenix.Component

  import Phoenix.LiveView, only: [push_event: 3, connected?: 1]

  alias Octopus.ColorPalette
  alias Octopus.Layout.Mildenberg
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
      data-pixel-image-url={@pixel_layout.pixel_image}
      style={"background-image: url(#{@pixel_layout.background_image});"}
    />
    """
  end

  @doc """
  Mounts the component.

  Sets up the layout, config, and pubsub subscribptions.
  """
  def mount(socket) do
    if connected?(socket) do
      Mixer.subscribe()
    end

    layout = Mildenberg.layout()
    config = @default_config

    frame = %Frame{
      data: List.duplicate(0, layout.width * layout.height),
      palette: ColorPalette.from_file("pico-8")
    }

    socket
    |> assign(pixel_layout: layout)
    |> push_layout(layout)
    |> push_config(config)
    |> push_frame(frame)
  end

  @doc """
  Returns the temporary assigns that should be passed to the parent live view.
  """
  def temporary_assigns do
    [pixel_layout: %{}]
  end

  @doc """
  Pushes a layout to the client.
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

  defmacro __using__(_) do
    quote do
      import unquote(__MODULE__), except: [mount: 1, temporary_assigns: 0]
    end
  end
end
