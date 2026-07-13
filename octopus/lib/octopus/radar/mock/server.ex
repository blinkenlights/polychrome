defmodule Octopus.Radar.Mock.Server do
  @moduledoc """
  In-process fake HLK-LD6001A device for radar mock mode.

  One `Mock.Server` stands in for one physical sensor. It behaves like the
  hardware at the wire level: it accepts AT command bytes, answers each with
  `AT+OK\\r\\n`, and — once `AT+START` has been received — streams binary
  `AT+DEBUG=3` frames built from the shared `Octopus.Radar.Mock.World`.

  Because the device only streams after the full AT init sequence, the owning
  `Octopus.Radar.Sensor` exercises its real probe → configure → run handshake
  against the mock, which is exactly what we want to test.

  The frames carry **sensor-local** coordinates: each world object (expressed
  globally) is mapped into this sensor's local frame via
  `Transform.global_to_local_track/2`, so when the `Sensor` applies the
  forward `Transform` it reconstructs the true global position. In `:exact`
  mode this is lossless (all sensors agree); in `:fuzzy` mode per-sensor bias,
  distance-scaled jitter and distance-based dropout are injected first.

  Received frames are delivered to the owning sensor as
  `{:circuits_uart, port, bytes}` — the same shape `Circuits.UART` uses — via
  `Octopus.Radar.Transport.Mock`.
  """

  use GenServer

  alias Octopus.Radar.{Frame, Protocol, Track, Transform}
  alias Octopus.Radar.Mock.World

  @emit_interval_ms 100

  # Fuzzy-mode noise model.
  @bias_offset_m 0.05
  @bias_rotation_deg 2.0
  @jitter_base_m 0.01
  @jitter_per_m 0.01
  @max_dropout 0.85

  ## Client API

  def start_link(opts) do
    gen_opts = case Keyword.get(opts, :name) do
      nil -> []
      name -> [name: name]
    end

    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc "Attach an owning sensor process; received bytes will be sent to `owner`."
  @spec attach(GenServer.server(), pid(), String.t()) :: :ok
  def attach(server, owner, port), do: GenServer.call(server, {:attach, owner, port})

  @doc "Write AT command bytes to the device."
  @spec write(GenServer.server(), iodata()) :: :ok
  def write(server, data), do: GenServer.cast(server, {:write, IO.iodata_to_binary(data)})

  @doc "Detach the current owner and stop streaming."
  @spec detach(GenServer.server()) :: :ok
  def detach(server), do: GenServer.call(server, :detach)

  @doc "Replace the mock device's pose config used for coordinate transforms."
  @spec update_config(GenServer.server(), keyword()) :: :ok
  def update_config(server, config) when is_list(config) do
    GenServer.call(server, {:update_config, config})
  end

  ## GenServer callbacks

  @impl true
  def init(opts) do
    config = Keyword.fetch!(opts, :config)

    state = %{
      device_id: Keyword.fetch!(opts, :device_id),
      config: config,
      mode: Keyword.get(opts, :mode, :exact),
      owner: nil,
      port: nil,
      ack_buffer: <<>>,
      emitting?: false,
      frame_number: 0,
      range_cm: Keyword.get(config, :range_cm, 450),
      bias: draw_bias()
    }

    Process.send_after(self(), :emit, @emit_interval_ms)
    {:ok, state}
  end

  @impl true
  def handle_call({:attach, owner, port}, _from, state) do
    {:reply, :ok,
     %{state | owner: owner, port: port, ack_buffer: <<>>, emitting?: false, frame_number: 0}}
  end

  def handle_call(:detach, _from, state) do
    {:reply, :ok, %{state | owner: nil, emitting?: false}}
  end

  def handle_call({:update_config, config}, _from, state) do
    {:reply, :ok, %{state | config: config}}
  end

  @impl true
  def handle_cast({:write, data}, state) do
    {:noreply, handle_at_bytes(data, state)}
  end

  @impl true
  def handle_info(:emit, state) do
    Process.send_after(self(), :emit, @emit_interval_ms)

    if state.emitting? and is_pid(state.owner) do
      {:noreply, emit_frame(state)}
    else
      {:noreply, state}
    end
  end

  ## AT command handling

  defp handle_at_bytes(data, state) do
    buffer = state.ack_buffer <> data
    {lines, rest} = split_lines(buffer)
    state = %{state | ack_buffer: rest}
    Enum.reduce(lines, state, &handle_at_line/2)
  end

  defp split_lines(buffer), do: do_split_lines(buffer, [])

  defp do_split_lines(buffer, acc) do
    case :binary.match(buffer, "\n") do
      :nomatch ->
        {Enum.reverse(acc), buffer}

      {pos, _} ->
        line = binary_part(buffer, 0, pos) |> String.trim_trailing("\r")
        rest = binary_part(buffer, pos + 1, byte_size(buffer) - pos - 1)
        do_split_lines(rest, [line | acc])
    end
  end

  defp handle_at_line("", state), do: state

  defp handle_at_line(line, state) do
    state =
      cond do
        String.contains?(line, "AT+START") ->
          %{state | emitting?: true}

        String.contains?(line, "AT+STOP") ->
          %{state | emitting?: false}

        String.starts_with?(line, "AT+RANGE=") ->
          case Integer.parse(String.trim_leading(line, "AT+RANGE=")) do
            {range_cm, _} -> %{state | range_cm: range_cm}
            :error -> state
          end

        true ->
          state
      end

    # Acknowledge every command line, exactly like the real device.
    send_to_owner(state, "AT+OK\r\n")
    state
  end

  ## Frame emission

  defp emit_frame(state) do
    tracks =
      World.objects()
      |> Enum.flat_map(&detect(&1, state))

    frame = %Frame{
      frame_number: state.frame_number,
      tracks: tracks,
      received_at: System.monotonic_time(:millisecond)
    }

    send_to_owner(state, Protocol.encode_frame(frame))
    %{state | frame_number: state.frame_number + 1}
  end

  # Turn one global world object into zero or one sensor-local track for this
  # sensor, honoring range clipping and (in fuzzy mode) noise/dropout.
  defp detect(obj, state) do
    global = %Track{
      id: obj.id,
      reserved: 0,
      x: obj.x,
      y: obj.y,
      z: obj.z,
      vx: obj.vx,
      vy: obj.vy,
      vz: 0.0
    }

    local = Transform.global_to_local_track(global, state.config)
    dist = :math.sqrt(local.x * local.x + local.y * local.y)
    range_m = state.range_cm / 100.0

    cond do
      dist > range_m -> []
      state.mode == :exact -> [local]
      dropped?(dist, range_m) -> []
      true -> [fuzz(local, dist, state.bias)]
    end
  end

  defp dropped?(dist, range_m) when range_m > 0 do
    p = min(@max_dropout, :math.pow(dist / range_m, 2) * 0.8)
    :rand.uniform() < p
  end

  defp dropped?(_dist, _range_m), do: false

  # Apply this sensor's fixed bias plus distance-scaled Gaussian jitter.
  defp fuzz(%Track{} = local, dist, bias) do
    cos_b = :math.cos(bias.rot_rad)
    sin_b = :math.sin(bias.rot_rad)

    bx = local.x * cos_b - local.y * sin_b + bias.dx
    by = local.x * sin_b + local.y * cos_b + bias.dy

    std = @jitter_base_m + @jitter_per_m * dist

    %Track{
      local
      | x: bx + rand_normal(std),
        y: by + rand_normal(std),
        z: local.z + rand_normal(std)
    }
  end

  defp draw_bias do
    %{
      dx: (:rand.uniform() * 2.0 - 1.0) * @bias_offset_m,
      dy: (:rand.uniform() * 2.0 - 1.0) * @bias_offset_m,
      rot_rad: (:rand.uniform() * 2.0 - 1.0) * @bias_rotation_deg * :math.pi() / 180.0
    }
  end

  # Box-Muller transform for a normal sample with the given standard deviation.
  defp rand_normal(std) do
    u1 = max(:rand.uniform(), 1.0e-12)
    u2 = :rand.uniform()
    std * :math.sqrt(-2.0 * :math.log(u1)) * :math.cos(2.0 * :math.pi() * u2)
  end

  defp send_to_owner(%{owner: owner, port: port}, bytes) when is_pid(owner) do
    send(owner, {:circuits_uart, port, bytes})
    :ok
  end

  defp send_to_owner(_state, _bytes), do: :ok
end
