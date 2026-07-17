defmodule Octopus.Radar.SensorDataForwarder do
  use GenServer
  require Logger
  alias Octopus.Radar
  alias Octopus.Protobuf
  alias Octopus.Protobuf.{ForwardedSensorDataPacket, ForwardedSensorMetadata, ForwardedSensorData, ForwardedTrack}

  @default_interval 100
  @default_port 5555
  @pubsub_topic "radar:sensor_data_forwarder"

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def port do
    Application.get_env(:octopus, :radar_sensor_data_forward_port, @default_port)
  end

  def subscribe do
    Phoenix.PubSub.subscribe(Octopus.PubSub, @pubsub_topic)
  end

  def add_subscriber(ip, timeout_minutes) do
    if running?() do
      GenServer.call(__MODULE__, {:add_subscriber, ip, timeout_minutes})
    else
      {:error, :not_running}
    end
  end

  def remove_subscriber(ip) do
    if running?() do
      GenServer.call(__MODULE__, {:remove_subscriber, ip})
    else
      {:error, :not_running}
    end
  end

  def start_push(ip) do
    if running?() do
      GenServer.call(__MODULE__, {:start_push, ip})
    else
      {:error, :not_running}
    end
  end

  def stop_push(ip) do
    if running?() do
      GenServer.call(__MODULE__, {:stop_push, ip})
    else
      {:error, :not_running}
    end
  end

  def get_subscribers do
    if running?() do
      GenServer.call(__MODULE__, :get_subscribers)
    else
      %{}
    end
  end

  defp running? do
    Process.whereis(__MODULE__) != nil
  end

  def init(:ok) do
    if Radar.configured?() do
      Radar.subscribe()
    end

    {:ok, udp} = :gen_udp.open(0, [:binary, active: false])

    interval = Application.get_env(:octopus, :radar_sensor_data_forward_interval, @default_interval)
    schedule_tick(interval)

    {:ok,
     %{
       udp: udp,
       subscribers: %{},
       last_frames: %{},
       interval: interval
     }}
  end

  def handle_call({:add_subscriber, ip, timeout_minutes}, _from, state) do
    Logger.info("[radar.forwarder] Adding subscriber: #{ip} (timeout: #{timeout_minutes} min)")

    subscribers =
      Map.put(state.subscribers, ip, %{
        timeout_minutes: timeout_minutes,
        active_until: nil
      })

    broadcast(subscribers)
    {:reply, :ok, %{state | subscribers: subscribers}}
  end

  def handle_call({:remove_subscriber, ip}, _from, state) do
    Logger.info("[radar.forwarder] Removing subscriber: #{ip}")
    subscribers = Map.delete(state.subscribers, ip)
    broadcast(subscribers)
    {:reply, :ok, %{state | subscribers: subscribers}}
  end

  def handle_call({:start_push, ip}, _from, state) do
    case Map.get(state.subscribers, ip) do
      nil ->
        {:reply, {:error, :not_found}, state}

      sub ->
        Logger.info("[radar.forwarder] Starting push for: #{ip}")
        active_until = DateTime.add(DateTime.utc_now(), sub.timeout_minutes, :minute)
        subscribers = Map.put(state.subscribers, ip, %{sub | active_until: active_until})
        broadcast(subscribers)
        {:reply, :ok, %{state | subscribers: subscribers}}
    end
  end

  def handle_call({:stop_push, ip}, _from, state) do
    case Map.get(state.subscribers, ip) do
      nil ->
        {:reply, {:error, :not_found}, state}

      sub ->
        Logger.info("[radar.forwarder] Stopping push for: #{ip}")
        subscribers = Map.put(state.subscribers, ip, %{sub | active_until: nil})
        broadcast(subscribers)
        {:reply, :ok, %{state | subscribers: subscribers}}
    end
  end

  def handle_call(:get_subscribers, _from, state) do
    {:reply, state.subscribers, state}
  end

  def handle_info({:radar_frame, device_id, frame}, state) do
    last_frames = Map.put(state.last_frames, device_id, frame)
    {:noreply, %{state | last_frames: last_frames}}
  end

  def handle_info(:push_tick, state) do
    now = DateTime.utc_now()

    active_subs =
      Enum.filter(state.subscribers, fn {_, sub} ->
        sub.active_until && DateTime.compare(sub.active_until, now) == :gt
      end)

    if active_subs != [] do
      try do
        push_data(state, active_subs)
      rescue
        e -> Logger.error("[radar.forwarder] Failed to push data: #{inspect(e)}")
      end
    end

    # Reset active_until for expired subscribers
    subscribers =
      Enum.into(state.subscribers, %{}, fn {ip, sub} ->
        if sub.active_until && DateTime.compare(sub.active_until, now) != :gt do
          {ip, %{sub | active_until: nil}}
        else
          {ip, sub}
        end
      end)

    if subscribers != state.subscribers do
      broadcast(subscribers)
    end

    schedule_tick(state.interval)
    {:noreply, %{state | subscribers: subscribers}}
  end

  defp push_data(state, active_subs) do
    devices = Radar.devices()

    sensors_meta =
      Enum.map(devices, fn dev ->
        %ForwardedSensorMetadata{
          device_id: dev.device_id,
          name: "Sensor #{dev.device_id}",
          rotation: dev.rotation_deg
        }
      end)

    sensors_data =
      Enum.map(state.last_frames, fn {device_id, frame} ->
        %ForwardedSensorData{
          device_id: device_id,
          tracks:
            Enum.map(frame.tracks, fn t ->
              %ForwardedTrack{
                id: t.id,
                x: t.x,
                y: t.y,
                z: t.z,
                vx: t.vx,
                vy: t.vy,
                vz: t.vz
              }
            end)
        }
      end)

    packet = %ForwardedSensorDataPacket{
      version: 1,
      num_sensors: length(devices),
      sensors: sensors_meta,
      data: sensors_data
    }

    binary = Protobuf.encode(packet)

    for {dest_str, _} <- active_subs do
      dest = String.to_charlist(dest_str)

      case :gen_udp.send(state.udp, dest, port(), binary) do
        :ok ->
          :ok

        {:error, reason} ->
          Logger.error("Failed to send UDP to #{dest_str}: #{inspect(reason)}")
      end
    end
  end

  defp schedule_tick(interval) do
    Process.send_after(self(), :push_tick, interval)
  end

  defp broadcast(subscribers) do
    Phoenix.PubSub.broadcast(Octopus.PubSub, @pubsub_topic, {:sensor_data_subscribers, subscribers})
  end
end
