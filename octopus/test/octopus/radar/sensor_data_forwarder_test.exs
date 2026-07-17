defmodule Octopus.Radar.SensorDataForwarderTest do
  use ExUnit.Case, async: true
  alias Octopus.Radar.SensorDataForwarder
  alias Octopus.Protobuf
  alias Octopus.Protobuf.{ForwardedSensorDataPacket, ForwardedSensorMetadata, ForwardedSensorData, ForwardedTrack}

  test "encodes and decodes ForwardedSensorDataPacket correctly" do
    data = %ForwardedSensorDataPacket{
      version: 1,
      num_sensors: 1,
      sensors: [
        %ForwardedSensorMetadata{device_id: 1, name: "Test Sensor", rotation: 0.0}
      ],
      data: [
        %ForwardedSensorData{
          device_id: 1,
          tracks: [
            %ForwardedTrack{id: 1, x: 1.0, y: 2.0, z: 3.0}
          ]
        }
      ]
    }

    encoded = Protobuf.encode(data)
    assert is_binary(encoded)

    {:ok, decoded} = Protobuf.decode_forwarded_packet(encoded)
    assert decoded == data
  end

  test "subscriber management" do
    if Process.whereis(SensorDataForwarder) do
      Process.exit(Process.whereis(SensorDataForwarder), :kill)
    end
    start_supervised!(SensorDataForwarder)

    :ok = SensorDataForwarder.add_subscriber("127.0.0.1", 10)
    subs = SensorDataForwarder.get_subscribers()
    assert Map.has_key?(subs, "127.0.0.1")
    assert subs["127.0.0.1"].timeout_minutes == 10
    assert subs["127.0.0.1"].active_until == nil

    :ok = SensorDataForwarder.start_push("127.0.0.1")
    subs = SensorDataForwarder.get_subscribers()
    assert subs["127.0.0.1"].active_until != nil

    :ok = SensorDataForwarder.stop_push("127.0.0.1")
    subs = SensorDataForwarder.get_subscribers()
    assert subs["127.0.0.1"].active_until == nil

    :ok = SensorDataForwarder.add_subscriber("localhost", 5)
    subs = SensorDataForwarder.get_subscribers()
    assert Map.has_key?(subs, "localhost")
    assert subs["localhost"].timeout_minutes == 5

    :ok = SensorDataForwarder.remove_subscriber("localhost")
    subs = SensorDataForwarder.get_subscribers()
    assert Map.has_key?(subs, "127.0.0.1")
    assert not Map.has_key?(subs, "localhost")

    :ok = SensorDataForwarder.remove_subscriber("127.0.0.1")
    subs = SensorDataForwarder.get_subscribers()
    assert subs == %{}
  end

  test "PubSub broadcasting" do
    if Process.whereis(SensorDataForwarder) do
      Process.exit(Process.whereis(SensorDataForwarder), :kill)
    end
    start_supervised!(SensorDataForwarder)
    SensorDataForwarder.subscribe()

    :ok = SensorDataForwarder.add_subscriber("1.2.3.4", 5)
    assert_receive {:sensor_data_subscribers, subs}
    assert Map.has_key?(subs, "1.2.3.4")

    :ok = SensorDataForwarder.start_push("1.2.3.4")
    assert_receive {:sensor_data_subscribers, subs}
    assert subs["1.2.3.4"].active_until != nil
  end

  test "port configuration" do
    assert SensorDataForwarder.port() == 5555

    Application.put_env(:octopus, :radar_sensor_data_forward_port, 6666)
    assert SensorDataForwarder.port() == 6666

    Application.delete_env(:octopus, :radar_sensor_data_forward_port)
    assert SensorDataForwarder.port() == 5555
  end
end
