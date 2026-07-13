defmodule OctopusWeb.Sim3dAframeLive do
  use OctopusWeb, :live_view

  alias Octopus.Mixer
  alias Octopus.Protobuf.{FirmwareConfig, RGBFrame}
  alias Octopus.Params.Sim3d, as: Params
  alias Octopus.Installation
  alias Octopus.Radar
  alias Octopus.Radar.Frame
  alias Octopus.Radar.Mock.World

  @default_config %FirmwareConfig{
    easing_mode: :LINEAR,
    show_test_frame: false
  }

  @id_prefix "sim_3d_aframe"

  @panel_param_keys [
    :diameter,
    :radar_count,
    :radar_height,
    :radar_tilt_deg,
    :radar_arm_length_m,
    :mast_diameter_m,
    :platform_radius_m,
    :lean_post_bottom_r,
    :lean_post_top_r,
    :lean_post_height,
    :height,
    :foot_diameter,
    :render_radar_cones,
    :radar_cone_straight_down
  ]

  def mount(_params, _session, socket) do
    socket =
      if connected?(socket) do
        Mixer.subscribe()
        if Radar.configured?(), do: Radar.subscribe()

        frame = %RGBFrame{
          data: List.duplicate([0, 0, 0], 80 * 8) |> IO.iodata_to_binary()
        }

        Phoenix.PubSub.subscribe(Octopus.PubSub, Params.topic())

        source_mode = Radar.source_mode()
        if Radar.mock_mode() != :off, do: subscribe_world()

        socket
        |> push_config(@default_config)
        |> push_frame(frame)
        |> push_initial_params()
        |> maybe_push_mock_world(source_mode)
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
    <div class="relative w-full min-h-screen">
      <div
        id={"#{@id_prefix}-#{@id}"}
        num-panels={@num_panels}
        class="flex w-full min-h-screen"
        phx-hook="Pixels3dAframe"
      >
      </div>
      <details
        open
        class="fixed top-2 right-2 z-50 w-80 max-h-[calc(100vh-1rem)] overflow-y-auto rounded-box bg-base-100/90 shadow-xl backdrop-blur"
      >
        <summary class="cursor-pointer select-none px-4 py-2 font-bold">Config</summary>
        <div class="px-4 pb-4">
          <.live_component id="sim3d-params" module={OctopusWeb.Sim3dParamsComponent} />
        </div>
      </details>
    </div>
    """
  end

  def handle_info({key, value}, socket) when key in @panel_param_keys do
    send_update(OctopusWeb.Sim3dParamsComponent, id: "sim3d-params")
    {:noreply, push_param(socket, %{key => value})}
  end

  def handle_info({:move, move}, socket) do
    {:noreply, push_param(socket, %{move: move})}
  end

  def handle_info({:position, position}, socket) do
    {:noreply, push_param(socket, %{position: position})}
  end

  def handle_info({:pole_diameter, value}, socket) do
    {:noreply, push_param(socket, %{pole_diameter: value})}
  end

  def handle_info({:button_diameter, value}, socket) do
    {:noreply, push_param(socket, %{button_diameter: value})}
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

  def handle_info({:radar_frame, device_id, %Frame{} = frame}, socket) do
    payload = %{
      device_id: device_id,
      frame_number: frame.frame_number,
      tracks:
        Enum.map(frame.tracks, fn t ->
          %{id: t.id, x: t.x, y: t.y, z: t.z, vx: t.vx, vy: t.vy, vz: t.vz}
        end)
    }

    {:noreply, push_radar_frame(socket, payload)}
  end

  def handle_info({:source_mode_changed, mode}, socket) do
    handle_source_mode_changed(socket, mode)
  end

  def handle_info({:mock_mode_changed, :off}, socket) do
    handle_source_mode_changed(socket, :live)
  end

  def handle_info({:mock_mode_changed, mode}, socket) when mode in [:exact, :fuzzy] do
    handle_source_mode_changed(socket, mode)
  end

  def handle_info({:mock_world, objects}, socket) do
    {:noreply, push_mock_world(socket, objects)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp handle_source_mode_changed(socket, mode) do
    if connected?(socket) do
      if mode in [:exact, :fuzzy], do: subscribe_world(), else: unsubscribe_world()
    end

    socket =
      if mode in [:exact, :fuzzy] do
        push_mock_world(socket, mock_world_objects())
      else
        push_mock_world(socket, [])
      end

    {:noreply, socket}
  end

  defp push_frame(socket, frame) do
    push_event(socket, "frame:#{@id_prefix}-#{socket.id}", %{frame: frame})
  end

  defp push_config(socket, config) do
    push_event(socket, "config:#{@id_prefix}-#{socket.id}", %{config: config})
  end

  defp push_initial_params(socket) do
    Enum.reduce(Params.config(), socket, fn {key, value}, acc ->
      push_param(acc, %{key => value})
    end)
  end

  defp push_param(socket, param) do
    push_event(socket, "param:#{@id_prefix}-#{socket.id}", %{param: param})
  end

  defp push_radar_frame(socket, payload) do
    push_event(socket, "radar_frame:#{@id_prefix}-#{socket.id}", payload)
  end

  defp push_mock_world(socket, objects) when is_list(objects) do
    push_event(socket, "mock_world:#{@id_prefix}-#{socket.id}", %{
      objects: serialize_mock_objects(objects)
    })
  end

  defp maybe_push_mock_world(socket, mode) when mode in [:exact, :fuzzy] do
    push_mock_world(socket, mock_world_objects())
  end

  defp maybe_push_mock_world(socket, _mode), do: socket

  defp mock_world_objects do
    case Process.whereis(World) do
      nil -> []
      _pid -> World.objects()
    end
  end

  defp serialize_mock_objects(objects) do
    Enum.map(objects, fn o ->
      %{
        id: o.id,
        x: o.x,
        y: o.y,
        z: Map.get(o, :z, 1.7),
        vx: Map.get(o, :vx, 0.0),
        vy: Map.get(o, :vy, 0.0)
      }
    end)
  end

  defp subscribe_world, do: Phoenix.PubSub.subscribe(Octopus.PubSub, World.world_topic())
  defp unsubscribe_world, do: Phoenix.PubSub.unsubscribe(Octopus.PubSub, World.world_topic())
end
