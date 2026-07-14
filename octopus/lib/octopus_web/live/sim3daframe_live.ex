defmodule OctopusWeb.Sim3dAframeLive do
  use OctopusWeb, :live_view

  alias Octopus.Mixer
  alias Octopus.Protobuf.{FirmwareConfig, RGBFrame}
  alias Octopus.Params.Sim3d, as: Params
  alias Octopus.Installation
  alias Octopus.Radar
  alias Octopus.Radar.Frame
  alias Octopus.Radar.Mock.World
  alias Octopus.Radar.PanelMapping

  @default_config %FirmwareConfig{
    easing_mode: :LINEAR,
    show_test_frame: false
  }

  @id_prefix "sim_3d_aframe"

  @panel_param_keys [
    :lean_post_bottom_r,
    :lean_post_top_r,
    :lean_post_height,
    :height,
    :foot_diameter
  ]

  def mount(_params, _session, socket) do
    socket =
      if connected?(socket) do
        Mixer.subscribe()

        if Radar.configured?() do
          Radar.subscribe()
          Radar.subscribe_panel_activity()
        end

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
        |> push_installation()
        |> maybe_push_mock_world(source_mode)
        |> maybe_push_panel_activity()
      else
        socket
      end

    {:ok,
     assign(socket,
       id: socket.id,
       id_prefix: @id_prefix,
       num_panels: Installation.num_panels(),
       installation_json: installation_json()
     )}
  end

  def render(assigns) do
    ~H"""
    <div class="relative w-full min-h-screen">
      <div
        id={"#{@id_prefix}-#{@id}"}
        num-panels={@num_panels}
        data-installation={@installation_json}
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

  def handle_info({:render_radar_cones, value}, socket) do
    send_update(OctopusWeb.Sim3dParamsComponent, id: "sim3d-params")
    {:noreply, push_param(socket, %{render_radar_cones: value})}
  end

  def handle_info({:render_panel_sectors, value}, socket) do
    send_update(OctopusWeb.Sim3dParamsComponent, id: "sim3d-params")
    {:noreply, push_param(socket, %{render_panel_sectors: value})}
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

  def handle_info({:panel_activity, snapshot}, socket) do
    {:noreply, push_panel_activity(socket, snapshot)}
  end

  def handle_info({:view_settings_changed, _settings}, socket) do
    {:noreply,
     socket
     |> assign(installation_json: installation_json())
     |> push_installation()}
  end

  def handle_info({:pose_tweak_changed, _tweak}, socket) do
    {:noreply, push_installation(socket)}
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

  # Authoritative installation geometry for the 3D scene: panel ring, panel
  # outer dimensions, north panel, platform, and the planned radar sensor poses.
  # Sensors are placed at their real global mount positions (see Radar.Transform)
  # and always look straight down.
  defp push_installation(socket) do
    push_event(socket, "installation:#{@id_prefix}-#{socket.id}", installation_payload())
  end

  defp installation_json, do: Jason.encode!(installation_payload())

  # Same geometry as radar_live build_ring_panels / sensor_position so the 3D
  # scene matches the 2D radar view exactly.
  defp installation_payload do
    {panel_width_m, panel_depth_m} = panel_dimensions_m()
    ring_radius_m = ring_radius_m()
    num_panels = Installation.num_panels()
    north_panel = Radar.north_panel()
    depth_m = panel_depth_m || 0.0
    panels = panel_slots(ring_radius_m, num_panels, north_panel, depth_m)

    %{
      ring_radius_m: ring_radius_m,
      num_panels: num_panels,
      north_panel: north_panel,
      platform_radius_m: Installation.platform_radius_m(),
      panel_width_m: panel_width_m,
      panel_depth_m: panel_depth_m,
      canvas_to_texture: PanelMapping.canvas_to_texture(num_panels, north_panel),
      panel_sectors: panel_sectors(num_panels, north_panel),
      panels: panels,
      sensors: installation_sensors()
    }
  end

  defp panel_sectors(num_panels, north_panel) do
    step_deg = 360.0 / num_panels
    half = step_deg / 2.0

    for sim <- 0..(num_panels - 1) do
      center_deg = sim / num_panels * 360.0

      %{
        sim: sim,
        installation_panel: PanelMapping.installation_panel_of_sim(sim, num_panels, north_panel),
        frame_panel: PanelMapping.frame_panel_of_3d(sim, num_panels),
        start_deg: center_deg - half,
        end_deg: center_deg + half
      }
    end
  end

  defp panel_slots(nil, _num_panels, _north_panel, _panel_depth_m), do: []

  defp panel_slots(ring_radius_m, num_panels, north_panel, panel_depth_m) do
    center_r = ring_radius_m + panel_depth_m / 2.0
    step_deg = 360.0 / num_panels

    for i <- 0..(num_panels - 1) do
      n = i + 1
      offset = Integer.mod(n - north_panel, num_panels)
      theta_deg = offset * step_deg
      theta_rad = theta_deg * :math.pi() / 180.0

      %{
        index: i,
        panel_number: n,
        canvas_panel: PanelMapping.frame_panel_for_installation(n, num_panels, north_panel),
        x_m: center_r * :math.sin(theta_rad),
        z_m: center_r * :math.cos(theta_rad),
        rotation_y: theta_rad + :math.pi()
      }
    end
  end

  defp installation_sensors do
    if Radar.configured?() do
      Enum.map(Radar.planned_devices(), fn d ->
        angle_rad = d.angle_deg * :math.pi() / 180.0
        distance_m = d.distance_cm / 100.0

        %{
          device_id: d.device_id,
          angle_deg: d.angle_deg,
          rotation_deg: d.rotation_deg,
          distance_cm: d.distance_cm,
          range_cm: d.range_cm,
          height_cm: d.height_cm,
          x_m: distance_m * :math.cos(angle_rad),
          z_m: distance_m * :math.sin(angle_rad)
        }
      end)
    else
      []
    end
  end

  defp ring_radius_m do
    if Installation.arrangement() == :circular, do: Installation.ring_radius_m(), else: nil
  end

  defp panel_dimensions_m do
    case Installation.panel_outer_dimensions_cm() do
      {width_cm, _height_cm, depth_cm} -> {width_cm / 100.0, depth_cm / 100.0}
      _ -> {nil, nil}
    end
  end

  defp push_radar_frame(socket, payload) do
    push_event(socket, "radar_frame:#{@id_prefix}-#{socket.id}", payload)
  end

  defp push_mock_world(socket, objects) when is_list(objects) do
    push_event(socket, "mock_world:#{@id_prefix}-#{socket.id}", %{
      objects: serialize_mock_objects(objects)
    })
  end

  defp maybe_push_panel_activity(socket) do
    if Radar.configured?(), do: push_panel_activity(socket), else: socket
  end

  defp push_panel_activity(socket, snapshot \\ nil) do
    snapshot = snapshot || Radar.panel_activity()

    push_event(socket, "panel_activity:#{@id_prefix}-#{socket.id}", %{
      factors: Map.get(snapshot, :factors, %{}),
      raw: Map.get(snapshot, :raw, %{}),
      ref: Map.get(snapshot, :ref, 0.0)
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
