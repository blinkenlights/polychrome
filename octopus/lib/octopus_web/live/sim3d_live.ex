defmodule OctopusWeb.Sim3dLive do
  use OctopusWeb, :live_view

  alias Octopus.Mixer
  alias Octopus.Protobuf.{FirmwareConfig, RGBFrame}

  @default_config %FirmwareConfig{
    easing_mode: :LINEAR,
    show_test_frame: false
  }

  @id_prefix "sim3d"

  def mount(_params, _session, socket) do
    socket =
      if connected?(socket) do
        Mixer.subscribe()

        frame = %RGBFrame{
          data: List.duplicate([0, 0, 0], 80 * 8) |> IO.iodata_to_binary()
        }

        socket
        |> push_config(@default_config)
        |> push_frame(frame)
      else
        socket
      end

    {:ok, assign(socket, id: socket.id, id_prefix: @id_prefix)}
  end

  def render(assigns) do
    ~H"""
    <div id={"#{@id_prefix}-#{@id}"} class="flex w-full h-full" phx-hook="Pixels3d"></div>
    """
  end

  def handle_info({:mixer, {:frame, frame}}, socket) do
    {:noreply, socket |> push_frame(frame)}
  end

  def handle_info({:mixer, {:config, config}}, socket) do
    {:noreply, socket |> push_config(config)}
  end

  def handle_info({:mixer, _msg}, socket) do
    {:noreply, socket}
  end

  defp push_frame(socket, frame) do
    push_event(socket, "frame:#{@id_prefix}-#{socket.id}", %{frame: frame})
  end

  defp push_config(socket, config) do
    push_event(socket, "config:#{@id_prefix}-#{socket.id}", %{config: config})
  end
end
