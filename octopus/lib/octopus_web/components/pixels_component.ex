defmodule OctopusWeb.PixelsComponent do
  use Phoenix.Component

  import Phoenix.LiveView, only: [push_event: 3]

  attr(:id, :string, required: true)
  attr(:pixel_layout, Octopus.Layout, required: true)

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

  def push_layout(socket, layout, id \\ "*") do
    push_event(socket, "layout:#{id}", %{layout: layout})
  end

  def push_frame(socket, frame, id \\ "*") do
    push_event(socket, "frame:#{id}", %{frame: frame})
  end

  def push_config(socket, config, id \\ "*") do
    push_event(socket, "config:#{id}", %{config: config})
  end

  defmacro __using__(_) do
    quote do
      import unquote(__MODULE__)
    end
  end
end
