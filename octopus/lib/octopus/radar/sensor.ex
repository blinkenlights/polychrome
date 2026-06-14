defmodule Octopus.Radar.Sensor do
  @moduledoc """
  Per-device GenServer for one HLK-LD6001A-60G radar.

  Owns a single serial port, runs the documented initialization sequence,
  and stream-parses the `AT+DEBUG=3` binary protocol. Decoded frames are
  published to two Phoenix.PubSub topics:

    * `Octopus.Radar.topic()` – global, all sensors
    * `Octopus.Radar.topic(device_id)` – this sensor only

  The PubSub message envelope is `{:radar_frame, device_id, %Frame{}}`.

  Phase machine:

    * `:opening` – open the UART port. On `:enoent`/`:eaccess`/etc. retry
      every 5 seconds so a hot-unplug/replug recovers without crashing the
      whole supervision tree.
    * `:configuring` – send the §8.2 init sequence; bytes received in this
      phase are scanned for `AT+OK` / `Save Para Fail` acks amid any binary
      noise per §8.3.
    * `:running` – feed every received chunk into `Octopus.Radar.Protocol`,
      publish each parsed frame.
  """

  use GenServer
  require Logger

  alias Circuits.UART
  alias Octopus.Radar
  alias Octopus.Radar.{Ack, Command, Frame, Protocol, Transform}

  @reopen_interval :timer.seconds(5)
  @ack_timeout :timer.seconds(2)
  @open_stagger_ms 200
  @post_open_settle_ms 300
  @max_ack_retries 5
  @escalate_delay_ms 500
  @stop_command "AT+STOP\n"
  @reset_command "AT+RESET\n"

  defmodule State do
    @moduledoc false
    defstruct [
      :device_id,
      :port_name,
      :baud,
      :config,
      :uart,
      :phase,
      :pending_commands,
      :current_command,
      :buffer,
      :ack_buffer,
      :last_track_count,
      :ack_timer,
      ack_retries: 0
    ]
  end

  ## Client API

  @doc """
  Start a sensor GenServer.

  Required opts:

    * `:device_id` – the integer assigned by list position in the
      application config; used as the `Registry` key and tagged in PubSub
      messages.
    * `:port` – serial device path (e.g. `"/dev/tty.usbserial-0001"`).

  Other geometry/timing keys (`:baud`, `:height_cm`, ...) come from the
  merged config produced by `Octopus.Radar`. They are required.
  """
  def start_link(opts) when is_list(opts) do
    device_id = Keyword.fetch!(opts, :device_id)
    GenServer.start_link(__MODULE__, opts, name: via(device_id))
  end

  @doc """
  Set the long-range detection sensitivity (`AT+DPKTH`, 1..9). Triggers
  a full re-init of the device so the new value is applied cleanly and
  any in-flight tracker state is reset.
  """
  @spec set_sensitivity(pos_integer(), 1..9) :: :ok | {:error, :no_sensor}
  def set_sensitivity(device_id, level) when is_integer(level) and level in 1..9 do
    call_sensor(device_id, {:set_sensitivity, level})
  end

  @doc "Re-run the configured init sequence, resetting on-device tracker state."
  @spec reinitialize(pos_integer()) :: :ok | {:error, :no_sensor}
  def reinitialize(device_id) do
    call_sensor(device_id, :reinitialize)
  end

  @doc "Return the sensor's current phase (`:opening`, `:configuring`, or `:running`)."
  @spec get_phase(pos_integer()) ::
          {:ok, :opening | :configuring | :running} | {:error, :no_sensor | :unavailable}
  def get_phase(device_id) do
    call_sensor(device_id, :get_phase)
  end

  defp via(device_id) do
    {:via, Registry, {Octopus.Radar.Registry, device_id}}
  end

  defp call_sensor(device_id, message) do
    try do
      GenServer.call(via(device_id), message)
    catch
      :exit, {:noproc, _} -> {:error, :no_sensor}
      :exit, _ -> {:error, :unavailable}
    end
  end

  ## GenServer callbacks

  @impl true
  def init(opts) do
    device_id = Keyword.fetch!(opts, :device_id)

    state = %State{
      device_id: device_id,
      port_name: Keyword.fetch!(opts, :port),
      baud: Keyword.fetch!(opts, :baud),
      config: opts,
      phase: :opening,
      pending_commands: [],
      buffer: <<>>,
      ack_buffer: <<>>,
      last_track_count: nil
    }

    {:ok, uart} = UART.start_link()
    state = %State{state | uart: uart}

    stagger_ms = (device_id - 1) * @open_stagger_ms

    if stagger_ms > 0 do
      Process.send_after(self(), :open_port, stagger_ms)
      {:ok, state}
    else
      {:ok, state, {:continue, :open_port}}
    end
  end

  @impl true
  def handle_continue(:open_port, %State{} = state) do
    {:noreply, try_open(state)}
  end

  @impl true
  def handle_call({:set_sensitivity, level}, _from, %State{} = state) do
    new_config = Keyword.put(state.config, :sensitivity, level)
    state = %State{state | config: new_config}

    if port_open?(state) do
      log(state, :info, "Updating sensitivity to DPKTH=#{level} and re-initializing")
      {:reply, :ok, restart_init(state)}
    else
      log(state, :info, "Updating sensitivity to DPKTH=#{level} — will apply when port opens")
      {:reply, :ok, state}
    end
  end

  def handle_call(:reinitialize, _from, %State{} = state) do
    log(state, :info, "Re-initializing on operator request")
    {:reply, :ok, restart_init(state)}
  end

  # The port just opened successfully: pending_commands is populated but
  # :start_init hasn't fired yet (300 ms settle). From the outside this is
  # indistinguishable from :configuring — the device IS reachable and init
  # is imminent — so report :configuring rather than :opening.
  def handle_call(:get_phase, _from, %State{phase: :opening, pending_commands: [_ | _]} = state) do
    {:reply, {:ok, :configuring}, state}
  end

  def handle_call(:get_phase, _from, %State{phase: phase} = state) do
    {:reply, {:ok, phase}, state}
  end

  @impl true
  def handle_info(:open_port, %State{} = state) do
    {:noreply, try_open(state)}
  end

  def handle_info(:start_init, %State{} = state) do
    {:noreply, state |> Map.put(:phase, :configuring) |> send_next_command()}
  end

  def handle_info(:reopen_port, %State{} = state) do
    {:noreply, try_open(state)}
  end

  def handle_info(:escalate_reopen, %State{} = state) do
    {:noreply, schedule_reopen(close_port(state))}
  end

  def handle_info(:ack_timeout, %State{phase: :configuring} = state) do
    ack_retries = state.ack_retries + 1
    state = %State{state | ack_timer: nil, ack_retries: ack_retries}

    if ack_retries >= @max_ack_retries do
      log(
        state,
        :warning,
        "AT command stuck after #{ack_retries} retries (#{inspect(state.current_command)}) — escalating"
      )

      {:noreply, escalate_init_failure(state)}
    else
      log(state, :warning, "AT command timed out, resending: #{inspect(state.current_command)}")
      {:noreply, resend_command(state)}
    end
  end

  def handle_info(:ack_timeout, %State{} = state) do
    {:noreply, %State{state | ack_timer: nil}}
  end

  def handle_info({:circuits_uart, _port, {:error, reason}}, %State{} = state) do
    log(state, :warning, "UART error: #{inspect(reason)} — reopening")
    {:noreply, schedule_reopen(close_port(state))}
  end

  def handle_info({:circuits_uart, _port, data}, %State{phase: :configuring} = state)
      when is_binary(data) do
    {:noreply, handle_ack_bytes(data, state)}
  end

  def handle_info({:circuits_uart, _port, data}, %State{phase: :running} = state)
      when is_binary(data) do
    {:noreply, handle_data_bytes(data, state)}
  end

  def handle_info({:circuits_uart, _port, _data}, %State{} = state) do
    # Bytes arriving while we're :opening are dropped; a fresh init is in
    # progress and the buffers will be reset.
    {:noreply, state}
  end

  def handle_info(message, %State{} = state) do
    log(state, :debug, "Unhandled message: #{inspect(message)}")
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, %State{} = state) do
    _ = graceful_close(state)
    :ok
  end

  ## Phase: opening

  defp try_open(%State{uart: uart, port_name: port, baud: baud} = state) do
    case UART.open(uart, port,
           speed: baud,
           data_bits: 8,
           stop_bits: 1,
           parity: :none,
           flow_control: :none,
           active: true,
           framing: Circuits.UART.Framing.None
         ) do
      :ok ->
        log(state, :info, "Opened serial port at #{baud} baud")
        Process.send_after(self(), :start_init, @post_open_settle_ms)

        %State{
          state
          | phase: :opening,
            pending_commands: Command.init_sequence(state.config),
            buffer: <<>>,
            ack_buffer: <<>>,
            ack_retries: 0,
            last_track_count: nil,
            current_command: nil
        }

      {:error, reason} ->
        log(state, :warning, "Failed to open serial port (#{inspect(reason)}) — retrying in 5s")
        schedule_reopen(state)
    end
  end

  defp schedule_reopen(%State{} = state) do
    Process.send_after(self(), :reopen_port, @reopen_interval)

    %State{
      state
      | phase: :opening,
        pending_commands: [],
        current_command: nil,
        ack_retries: 0
    }
  end

  defp close_port(%State{uart: uart} = state) when is_pid(uart) do
    _ = UART.close(uart)
    cancel_ack_timer(state)

    %State{
      state
      | phase: :opening,
        buffer: <<>>,
        ack_buffer: <<>>,
        current_command: nil,
        ack_retries: 0
    }
  end

  defp close_port(state), do: state

  defp graceful_close(%State{uart: uart, phase: phase} = state)
       when is_pid(uart) and phase in [:configuring, :running] do
    _ = UART.write(uart, @stop_command)
    Process.sleep(100)
    close_port(state)
  end

  defp graceful_close(state), do: close_port(state)

  defp escalate_init_failure(%State{uart: uart} = state) when is_pid(uart) do
    _ = UART.write(uart, @reset_command)
    Process.send_after(self(), :escalate_reopen, @escalate_delay_ms)

    %State{
      state
      | phase: :opening,
        pending_commands: [],
        current_command: nil,
        ack_retries: 0
    }
  end

  defp escalate_init_failure(state), do: schedule_reopen(close_port(state))

  ## Phase: configuring

  defp send_next_command(%State{pending_commands: []} = state) do
    log(state, :info, "Initialization complete — entering :running phase")
    %State{state | phase: :running, current_command: nil, ack_buffer: <<>>, buffer: <<>>}
  end

  defp send_next_command(%State{pending_commands: [cmd | rest]} = state) do
    write_command(cmd, %State{state | pending_commands: rest, current_command: cmd})
  end

  # Drop any in-flight ack timer + parser buffers, then re-issue the full
  # init sequence. Residual binary frames may still arrive during
  # :configuring; Ack.feed/2 scans the mixed stream for AT+OK without
  # requiring a quiet line.
  defp port_open?(%State{phase: phase}), do: phase in [:configuring, :running]

  defp restart_init(%State{phase: :opening} = state) do
    log(state, :info, "Re-init deferred until serial port is available")

    cancel_ack_timer(%State{
      state
      | pending_commands: [],
        current_command: nil,
        buffer: <<>>,
        ack_buffer: <<>>,
        ack_retries: 0,
        last_track_count: nil
    })
  end

  defp restart_init(%State{} = state) do
    state = cancel_ack_timer(state)

    %State{
      state
      | phase: :configuring,
        pending_commands: Command.init_sequence(state.config),
        current_command: nil,
        buffer: <<>>,
        ack_buffer: <<>>,
        ack_retries: 0,
        last_track_count: nil
    }
    |> send_next_command()
  end

  defp write_command(cmd, %State{uart: uart} = state) do
    log(state, :info, "→ #{String.trim_trailing(cmd)}")

    case UART.write(uart, cmd) do
      :ok ->
        arm_ack_timer(%State{state | current_command: cmd, ack_buffer: <<>>})

      {:error, reason} ->
        log(state, :warning, "UART write failed (#{inspect(reason)}) — reopening")
        schedule_reopen(close_port(state))
    end
  end

  defp resend_command(%State{uart: uart, current_command: cmd} = state) do
    log(state, :info, "→ #{String.trim_trailing(cmd)}")

    case UART.write(uart, cmd) do
      :ok ->
        arm_ack_timer(state)

      {:error, reason} ->
        log(state, :warning, "UART write failed (#{inspect(reason)}) — reopening")
        schedule_reopen(close_port(state))
    end
  end

  defp handle_ack_bytes(data, %State{ack_buffer: ack_buffer} = state) do
    case Ack.feed(ack_buffer, data) do
      {:pending, buf} ->
        %State{state | ack_buffer: buf}

      {:ok, buf} ->
        log(state, :info, "← AT+OK")

        %State{} = state =
          state
          |> cancel_ack_timer()
          |> reset_ack_retries()
          |> then(fn %State{} = s -> %State{s | ack_buffer: buf} end)

        send_next_command(state)

      {:retry, buf} ->
        log(state, :warning, "← Save Para Fail — resending: #{inspect(state.current_command)}")

        %State{} = state =
          state
          |> cancel_ack_timer()
          |> reset_ack_retries()
          |> then(fn %State{} = s -> %State{s | ack_buffer: buf} end)

        write_command(state.current_command, state)
    end
  end

  defp reset_ack_retries(%State{} = state), do: %State{state | ack_retries: 0}

  defp arm_ack_timer(%State{} = state) do
    state = cancel_ack_timer(state)
    timer = Process.send_after(self(), :ack_timeout, @ack_timeout)
    %State{state | ack_timer: timer}
  end

  defp cancel_ack_timer(%State{ack_timer: nil} = state), do: state

  defp cancel_ack_timer(%State{ack_timer: ref} = state) do
    _ = Process.cancel_timer(ref)
    %State{state | ack_timer: nil}
  end

  ## Phase: running

  defp handle_data_bytes(data, %State{buffer: buffer} = state) do
    {frames, errors, leftover} = Protocol.feed(buffer, data)

    Enum.each(errors, fn {:error, reason, _frame_bin} ->
      log(state, :warning, "Frame parse error: #{reason}")
    end)

    %State{} = state = Enum.reduce(frames, state, &publish_frame/2)
    %State{state | buffer: leftover}
  end

  defp publish_frame(%Frame{} = frame, %State{device_id: device_id, config: config} = state) do
    frame = Transform.transform_frame(frame, config)
    envelope = {:radar_frame, device_id, frame}
    Phoenix.PubSub.broadcast(Octopus.PubSub, Radar.topic(), envelope)
    Phoenix.PubSub.broadcast(Octopus.PubSub, Radar.topic(device_id), envelope)

    track_count = length(frame.tracks)

    if track_count != state.last_track_count do
      ids = Enum.map_join(frame.tracks, ", ", &Integer.to_string(&1.id))

      log(
        state,
        :info,
        "Tracking #{track_count} person(s)" <>
          if(track_count > 0, do: " (target IDs: #{ids})", else: "")
      )

      # Diagnostic: print the per-record fields at offset 0 and offset 4 so we
      # can confirm field-order interpretation against actual hardware.
      # Per both the HLK-LD6001A V1.1 manual §7.2.1 and the MS72SF1 V1.0
      # datasheet §8.2, offset 0 is "reserved" and offset 4 is the track ID.
      # If the offset-0 column is always 0 in real captures, the docs (and our
      # parser) are correct. The nitram509/ld6001-ms72sf1-connector JS parser
      # has these reversed.
      if track_count > 0 do
        rows =
          Enum.map_join(frame.tracks, ", ", fn t ->
            "{off0=#{t.reserved}, off4=#{t.id}}"
          end)

        log(state, :debug, "track field diagnostic: #{rows}")
      end

      %State{state | last_track_count: track_count}
    else
      state
    end
  end

  ## Logging

  defp log(%State{device_id: id, port_name: port}, level, message) do
    Logger.log(level, "[radar #{id} #{port}] #{message}")
  end
end
