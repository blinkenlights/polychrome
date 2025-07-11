defmodule OctopusWeb.Sim3dAframeLive do
  use OctopusWeb, :live_view

  alias Octopus.Mixer
  alias Octopus.Protobuf.{FirmwareConfig, RGBFrame}
  alias Octopus.Params.Sim3d, as: Params
  alias Octopus.Installation

  @default_config %FirmwareConfig{
    easing_mode: :LINEAR,
    show_test_frame: false
  }

  @id_prefix "sim_3d_aframe"

  def mount(_params, _session, socket) do
    socket =
      if connected?(socket) do
        Mixer.subscribe()

        frame = %RGBFrame{
          data: List.duplicate([0, 0, 0], 80 * 8) |> IO.iodata_to_binary()
        }

        Phoenix.PubSub.subscribe(Octopus.PubSub, Octopus.Params.Sim3d.topic())

        socket
        |> push_config(@default_config)
        |> push_frame(frame)
        |> push_param(%{diameter: Params.diameter()})
        |> push_param(%{move: [0.0, 0.0]})
        |> push_param(%{position: Params.position()})
        |> push_param(%{height: Params.height()})
        |> push_param(%{pole_diameter: Params.pole_diameter()})
        |> push_param(%{foot_diameter: Params.foot_diameter()})
      else
        socket
      end

    {:ok,
     assign(socket,
       id: socket.id,
       id_prefix: @id_prefix,
       num_panels: Installation.num_panels()
     )}
  end

  def render(assigns) do
    ~H"""
    <div
      id={"#{@id_prefix}-#{@id}"}
      num-panels={@num_panels}
      class="flex w-full h-full"
      phx-hook="Pixels3dAframe"
    >
    </div>
    """
  end

  def handle_info({:diameter, value}, socket) do
    {:noreply, push_param(socket, %{diameter: value})}
  end

  def handle_info({:move, move}, socket) do
    {:noreply, push_param(socket, %{move: move})}
  end

  def handle_info({:position, position}, socket) do
    {:noreply, push_param(socket, %{position: position})}
  end

  def handle_info({:height, value}, socket) do
    {:noreply, push_param(socket, %{height: value})}
  end

  def handle_info({:pole_diameter, value}, socket) do
    {:noreply, push_param(socket, %{pole_diameter: value})}
  end

  def handle_info({:foot_diameter, value}, socket) do
    {:noreply, push_param(socket, %{foot_diameter: value})}
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

  defp push_param(socket, param) do
    push_event(socket, "param:#{@id_prefix}-#{socket.id}", %{param: param})
  end
end
