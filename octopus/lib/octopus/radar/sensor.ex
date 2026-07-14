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
    * `:stale` – port is open but the sensor has not yet been confirmed
      responsive. This is the entry state after the port opens (replacing an
      immediate jump to `:configuring`) and also the state the sensor falls
      back to when:
        - no frames arrive within `@frame_timeout_ms` while `:running`
        - the AT init sequence stops responding while `:configuring`
      In this phase, a minimal `AT` probe is sent repeatedly; on `AT+OK` the
      sensor advances to `:configuring`. After `@max_ack_retries` failures
      the port is closed and reopened (back to `:opening`).
    * `:configuring` – send the §8.2 init sequence; bytes received in this
      phase are scanned for `AT+OK` / `Save Para Fail` acks amid any binary
      noise per §8.3. If the sensor stops responding here it falls back to
      `:stale` to probe again before retrying the full sequence.
    * `:running` – feed every received chunk into `Octopus.Radar.Protocol`,
      publish each parsed frame.
  """

  use GenServer
  require Logger

  alias Octopus.Radar
  alias Octopus.Radar.{Ack, ClutterFilter, Command, Frame, LogFormat, Protocol, Transform}

  @reopen_interval :timer.seconds(5)
  @ack_timeout :timer.seconds(2)
  @open_stagger_ms 200
  @post_open_settle_ms 300
  @post_reset_settle_ms 1_000
  @probe_window_ms :timer.seconds(2)
  @max_ack_retries 5
  @stop_command "AT+STOP\n"
  @reset_command "AT+RESET\n"
  @frame_timeout_ms 3_000
  @probe_command "AT+STOP\n"

  defmodule State do
    @moduledoc false
    defstruct [
      :device_id,
      :port_name,
      :baud,
      :config,
      :transport,
      :uart,
      :phase,
      :pending_commands,
      :current_command,
      :buffer,
      :ack_buffer,
      :ack_timer,
      :last_frame_at,
      :watchdog_timer,
      :last_ui_status,
      ack_retries: 0,
      port_unavailable: false,
      recovery_stage: :normal
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
  Set the long-range detection sensitivity (device-native register value).
  Triggers a full re-init of the device so the new value is applied cleanly and
  any in-flight tracker state is reset.

  Prefer `Octopus.Radar.set_sensitivity_level/2` at call sites that use the
  UI scale (1 = least sensitive, 9 = most).
  """
  @spec set_sensitivity(pos_integer(), pos_integer()) :: :ok | {:error, :no_sensor}
  def set_sensitivity(device_id, device_value) when is_integer(device_value) do
    call_sensor(device_id, {:set_sensitivity, device_value})
  end

  @doc "Re-run the configured init sequence, resetting on-device tracker state."
  @spec reinitialize(pos_integer()) :: :ok | {:error, :no_sensor}
  def reinitialize(device_id) do
    call_sensor(device_id, :reinitialize)
  end

  @doc """
  Replace the sensor's merged runtime config (used for pose transforms).

  Only geometry keys are expected to change; device parameters such as
  sensitivity are left untouched by the caller.
  """
  @spec update_config(pos_integer(), keyword()) :: :ok | {:error, :no_sensor}
  def update_config(device_id, config) when is_list(config) do
    call_sensor(device_id, {:update_config, config})
  end

  @doc "Return the sensor's current phase (`:opening`, `:probing`, `:configuring`, `:running`, or `:stale`)."
  @spec get_phase(pos_integer()) ::
          {:ok, :opening | :probing | :configuring | :running | :stale}
          | {:error, :no_sensor | :unavailable}
  def get_phase(device_id) do
    call_sensor(device_id, :get_phase)
  end

  @doc "Return the UI-facing status atom for a sensor."
  @spec get_ui_status(pos_integer()) ::
          {:ok, :inactive | :unavailable | :probing | :initializing | :working | :stale}
          | {:error, :no_sensor | :unavailable}
  def get_ui_status(device_id) do
    call_sensor(device_id, :get_ui_status)
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
    transport = Keyword.get(opts, :transport, Octopus.Radar.Transport.UART)
    transport_opts = Keyword.get(opts, :transport_opts, [])

    state = %State{
      device_id: device_id,
      port_name: Keyword.fetch!(opts, :port),
      baud: Keyword.fetch!(opts, :baud),
      config: opts,
      transport: transport,
      phase: :opening,
      pending_commands: [],
      buffer: <<>>,
      ack_buffer: <<>>
    }

    {:ok, uart} = transport.start_link(transport_opts)
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
      log(state, :debug, "Sensitivity updated to DPKTH=#{level}, re-initializing")
      {:reply, :ok, restart_init(state)}
    else
      log(state, :debug, "Sensitivity updated to DPKTH=#{level} — will apply when port opens")
      {:reply, :ok, state}
    end
  end

  def handle_call(:reinitialize, _from, %State{} = state) do
    log(state, :debug, "Re-initializing on operator request")
    {:reply, :ok, restart_init(state)}
  end

  def handle_call({:update_config, config}, _from, %State{} = state) do
    {:reply, :ok, %{state | config: config}}
  end

  def handle_call(:get_phase, _from, %State{phase: phase} = state) do
    {:reply, {:ok, phase}, state}
  end

  def handle_call(:get_ui_status, _from, %State{} = state) do
    {:reply, {:ok, ui_status(state)}, state}
  end

  @impl true
  def handle_info(:open_port, %State{} = state) do
    {:noreply, try_open(state)}
  end

  def handle_info(:start_init, %State{} = state) do
    timer = Process.send_after(self(), :probe_window_expired, @probe_window_ms)
    state = set_status(state, :probing)

    {:noreply,
     %State{
       state
       | phase: :probing,
         buffer: <<>>,
         ack_buffer: <<>>,
         watchdog_timer: timer
     }}
  end

  def handle_info(:probe_window_expired, %State{phase: :probing} = state) do
    state = cancel_watchdog(state)

    case maybe_attach_from_probe_buffer(state) do
      {:attach, state} ->
        {:noreply, state}

      :no ->
        case state.recovery_stage do
          :post_reset ->
            {:noreply, enter_configuring(%State{state | recovery_stage: :normal})}

          :normal ->
            {:noreply, reset_then_init(state)}
        end
    end
  end

  def handle_info(:post_reset_init, %State{} = state) do
    timer = Process.send_after(self(), :probe_window_expired, @probe_window_ms)
    state = set_status(state, :probing)

    {:noreply,
     %State{
       state
       | phase: :probing,
         buffer: <<>>,
         ack_buffer: <<>>,
         recovery_stage: :post_reset,
         watchdog_timer: timer
     }}
  end

  def handle_info(:probe_window_expired, %State{} = state) do
    {:noreply, state}
  end

  def handle_info(:reopen_port, %State{} = state) do
    {:noreply, try_open(state)}
  end

  def handle_info(:escalate_reopen, %State{} = state) do
    # Close the port and reopen shortly — this drains OS+hardware UART buffers
    # and gives the device a fresh handshake which can break streaming devices
    # out of their unresponsive state.
    state = close_port(state)
    Process.send_after(self(), :reopen_port, @reopen_interval)
    {:noreply, state}
  end

  def handle_info(:ack_timeout, %State{phase: :configuring} = state) do
    ack_retries = state.ack_retries + 1
    state = %State{state | ack_timer: nil, ack_retries: ack_retries}

    if ack_retries >= @max_ack_retries do
      log(
        state,
        :debug,
        "Init command stuck after #{ack_retries} retries — falling back to stale"
      )

      state = %State{state | phase: :stale}
      {:noreply, state |> set_status(:stale) |> send_probe()}
    else
      case try_attach_from_ack_buffer(state) do
        {:attach, state} -> {:noreply, state}
        :no -> {:noreply, resend_command(state)}
      end
    end
  end

  def handle_info(:ack_timeout, %State{phase: :stale} = state) do
    ack_retries = state.ack_retries + 1
    state = %State{state | ack_timer: nil, ack_retries: ack_retries}

    if ack_retries >= @max_ack_retries do
      log(state, :debug, "Probe stuck after #{ack_retries} retries — reopening port")
      {:noreply, escalate_init_failure(state)}
    else
      case try_attach_from_ack_buffer(state) do
        {:attach, state} -> {:noreply, state}
        :no -> {:noreply, resend_command(state)}
      end
    end
  end

  def handle_info(:ack_timeout, %State{} = state) do
    {:noreply, %State{state | ack_timer: nil}}
  end

  def handle_info(:frame_watchdog, %State{phase: :running} = state) do
    state = %State{state | phase: :stale, watchdog_timer: nil}
    {:noreply, state |> set_status(:stale) |> send_probe()}
  end

  def handle_info(:frame_watchdog, %State{} = state) do
    {:noreply, %State{state | watchdog_timer: nil}}
  end

  def handle_info({:circuits_uart, _port, {:error, reason}}, %State{} = state) do
    log(state, :debug, "UART error: #{inspect(reason)} — reopening port")
    {:noreply, schedule_reopen(close_port(state))}
  end

  def handle_info({:circuits_uart, _port, data}, %State{phase: :probing} = state)
      when is_binary(data) do
    {:noreply, handle_probing_bytes(data, state)}
  end

  def handle_info({:circuits_uart, _port, data}, %State{phase: :configuring} = state)
      when is_binary(data) do
    {:noreply, handle_ack_bytes(data, state)}
  end

  def handle_info({:circuits_uart, _port, data}, %State{phase: :stale} = state)
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

  ## Phase: probing (passive observation — no AT commands sent)

  defp handle_probing_bytes(data, %State{buffer: buffer} = state) do
    case Protocol.feed(buffer, data) do
      {[_ | _], _, leftover} ->
        state |> cancel_watchdog() |> enter_running_from_stream(leftover)

      {[], _, leftover} ->
        %State{state | buffer: leftover}
    end
  end

  ## Phase: opening

  defp try_open(%State{transport: transport, uart: uart, port_name: port, baud: baud} = state) do
    case transport.open(uart, port,
           speed: baud,
           data_bits: 8,
           stop_bits: 1,
           parity: :none,
           flow_control: :none,
           active: true,
           framing: Circuits.UART.Framing.None
         ) do
      :ok ->
        Process.send_after(self(), :start_init, @post_open_settle_ms)
        state = set_status(state, :probing)

        %State{
          state
          | phase: :opening,
            pending_commands: [],
            buffer: <<>>,
            ack_buffer: <<>>,
            ack_retries: 0,
            current_command: nil,
            port_unavailable: false
        }

      {:error, reason} ->
        schedule_reopen(state, unavailable_reason: reason)
    end
  end

  defp schedule_reopen(state, opts \\ [])

  defp schedule_reopen(%State{port_unavailable: true} = state, _opts) do
    Process.send_after(self(), :reopen_port, @reopen_interval)

    %State{
      state
      | phase: :opening,
        pending_commands: [],
        current_command: nil,
        ack_retries: 0
    }
  end

  defp schedule_reopen(%State{} = state, _opts) do
    Process.send_after(self(), :reopen_port, @reopen_interval)
    state = set_status(state, :unavailable)

    %State{
      state
      | phase: :opening,
        pending_commands: [],
        current_command: nil,
        ack_retries: 0,
        port_unavailable: true
    }
  end

  defp close_port(%State{transport: transport, uart: uart} = state) when not is_nil(uart) do
    _ = transport.close(uart)
    state = cancel_ack_timer(state)
    state = cancel_watchdog(state)

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

  defp graceful_close(%State{transport: transport, uart: uart, phase: phase} = state)
       when not is_nil(uart) and phase in [:probing, :configuring, :running, :stale] do
    _ = transport.write(uart, @stop_command)
    Process.sleep(100)
    close_port(state)
  end

  defp graceful_close(state), do: close_port(state)

  defp escalate_init_failure(%State{transport: transport, uart: uart} = state)
       when not is_nil(uart) do
    # Best-effort stop/reset (ignored if the device is streaming), then close
    # the port entirely. Closing the OS file descriptor drains both the kernel
    # UART queue and the adapter hardware buffer, giving the device a fresh
    # handshake on reopen — the only software-level way to break a streaming
    # device out of its unresponsive state without a physical power cycle.
    _ = transport.write(uart, @reset_command)

    state
    |> cancel_ack_timer()
    |> cancel_watchdog()
    |> close_port()
    |> tap(fn _ -> Process.send_after(self(), :reopen_port, @reopen_interval) end)
  end

  defp escalate_init_failure(state), do: schedule_reopen(close_port(state))

  ## Phase: configuring

  defp send_next_command(%State{pending_commands: []} = state) do
    timer = Process.send_after(self(), :probe_window_expired, @probe_window_ms)
    state = set_status(state, :probing)

    %State{
      state
      | phase: :probing,
        current_command: nil,
        ack_buffer: <<>>,
        buffer: <<>>,
        watchdog_timer: timer
    }
  end

  defp send_next_command(%State{pending_commands: [cmd | rest]} = state) do
    write_command(cmd, %State{state | pending_commands: rest, current_command: cmd})
  end

  # Drop any in-flight ack timer + parser buffers, then re-issue the full
  # init sequence. Residual binary frames may still arrive during
  # :configuring; Ack.feed/2 scans the mixed stream for AT+OK without
  # requiring a quiet line.
  defp port_open?(%State{phase: phase}), do: phase in [:probing, :configuring, :running, :stale]

  defp restart_init(%State{phase: :opening} = state) do
    cancel_ack_timer(%State{
      state
      | pending_commands: [],
        current_command: nil,
        buffer: <<>>,
        ack_buffer: <<>>,
        ack_retries: 0,
        watchdog_timer: nil
    })
  end

  defp restart_init(%State{} = state) do
    state = cancel_ack_timer(state)
    state = cancel_watchdog(state)

    state = %State{
      state
      | phase: :stale,
        pending_commands: [],
        current_command: nil,
        buffer: <<>>,
        ack_buffer: <<>>,
        ack_retries: 0
    }

    state |> set_status(:stale) |> send_probe()
  end

  defp enter_configuring(%State{} = state) do
    state =
      %State{
        state
        | phase: :configuring,
          pending_commands: Command.init_sequence(state.config),
          current_command: nil,
          buffer: <<>>,
          ack_buffer: <<>>,
          ack_retries: 0
      }
      |> set_status(:initializing)

    send_next_command(state)
  end

  defp enter_running_from_stream(%State{} = state, buffer) do
    timer = Process.send_after(self(), :frame_watchdog, @frame_timeout_ms)

    %State{
      state
      | phase: :running,
        ack_buffer: <<>>,
        buffer: buffer,
        last_frame_at: System.monotonic_time(:millisecond),
        watchdog_timer: timer,
        current_command: nil,
        pending_commands: []
    }
    |> set_status(:working)
  end

  defp write_command(cmd, %State{transport: transport, uart: uart} = state) do
    case try_attach_from_ack_buffer(state) do
      {:attach, state} ->
        state

      :no ->
        case transport.write(uart, cmd) do
          :ok ->
            arm_ack_timer(%State{state | current_command: cmd, ack_buffer: <<>>})

          {:error, reason} ->
            log(state, :debug, "UART write failed (#{inspect(reason)}) — reopening port")
            schedule_reopen(close_port(state))
        end
    end
  end

  defp resend_command(%State{transport: transport, uart: uart} = state) do
    case transport.write(uart, state.current_command) do
      :ok ->
        arm_ack_timer(state)

      {:error, reason} ->
        log(state, :debug, "UART write failed (#{inspect(reason)}) — reopening port")
        schedule_reopen(close_port(state))
    end
  end

  defp handle_ack_bytes(data, %State{phase: phase} = state) when phase in [:stale, :configuring] do
    handle_ack_bytes_impl(data, state)
  end

  defp handle_ack_bytes_impl(data, %State{phase: :stale, ack_buffer: ack_buffer} = state) do
    case Ack.feed(ack_buffer, data) do
      {:pending, buf} ->
        case try_attach_from_binary(buf, state) do
          {:attach, state} ->
            state

          :no ->
            %State{state | ack_buffer: buf}
        end

      {:ok, _buf} ->
        state
        |> cancel_ack_timer()
        |> reset_ack_retries()
        |> enter_configuring()

      {:retry, buf} ->
        state
        |> cancel_ack_timer()
        |> reset_ack_retries()
        |> then(fn %State{} = s -> %State{s | ack_buffer: buf} end)
        |> enter_configuring()
    end
  end

  defp handle_ack_bytes_impl(data, %State{ack_buffer: ack_buffer} = state) do
    case Ack.feed(ack_buffer, data) do
      {:pending, buf} ->
        case try_attach_from_binary(buf, state) do
          {:attach, state} -> state
          :no -> %State{state | ack_buffer: buf}
        end

      {:ok, buf} ->
        %State{} =
          state =
          state
          |> cancel_ack_timer()
          |> reset_ack_retries()
          |> then(fn %State{} = s -> %State{s | ack_buffer: buf} end)

        send_next_command(state)

      {:retry, buf} ->
        %State{} =
          state =
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

  defp cancel_watchdog(%State{watchdog_timer: nil} = state), do: state

  defp cancel_watchdog(%State{watchdog_timer: ref} = state) do
    _ = Process.cancel_timer(ref)
    %State{state | watchdog_timer: nil}
  end

  defp send_probe(%State{} = state) do
    case try_attach_from_ack_buffer(state) do
      {:attach, state} ->
        state

      :no ->
        write_command(@probe_command, %State{state | ack_retries: 0})
    end
  end

  defp reset_then_init(%State{transport: transport, uart: uart} = state) when not is_nil(uart) do
    case transport.write(uart, @reset_command) do
      :ok ->
        Process.send_after(self(), :post_reset_init, @post_reset_settle_ms)

        %State{
          state
          | phase: :opening,
            ack_buffer: <<>>,
            buffer: <<>>,
            ack_retries: 0,
            recovery_stage: :post_reset
        }

      {:error, reason} ->
        log(state, :debug, "AT+RESET write failed (#{inspect(reason)}) — initializing anyway")
        enter_configuring(%State{state | recovery_stage: :normal})
    end
  end

  defp reset_then_init(%State{} = state), do: enter_configuring(%State{state | recovery_stage: :normal})

  defp maybe_attach_from_probe_buffer(%State{buffer: buffer} = state) do
    try_attach_from_binary(buffer, state)
  end

  defp try_attach_from_ack_buffer(%State{ack_buffer: ack_buffer} = state) do
    try_attach_from_binary(ack_buffer, state)
  end

  defp try_attach_from_binary(binary, %State{} = state) when is_binary(binary) and binary != <<>> do
    case Protocol.feed(<<>>, binary) do
      {[_ | _], _, leftover} ->
        log(state, :debug, "Binary stream detected — attaching without re-init")
        {:attach, state |> cancel_ack_timer() |> cancel_watchdog() |> enter_running_from_stream(leftover)}

      _ ->
        :no
    end
  end

  defp try_attach_from_binary(_binary, _state), do: :no

  defp ui_status(%State{phase: :opening, port_unavailable: true}), do: :unavailable
  defp ui_status(%State{phase: :opening}), do: :probing
  defp ui_status(%State{phase: :running}), do: :working
  defp ui_status(%State{phase: :stale}), do: :stale
  defp ui_status(%State{phase: :probing}), do: :probing
  defp ui_status(%State{phase: :configuring}), do: :initializing

  ## Phase: running

  defp handle_data_bytes(data, %State{buffer: buffer} = state) do
    {frames, errors, leftover} = Protocol.feed(buffer, data)

    Enum.each(errors, fn {:error, reason, _frame_bin} ->
      log(state, :debug, "Frame parse error: #{reason}")
    end)

    %State{} = state = Enum.reduce(frames, state, &publish_frame/2)
    %State{state | buffer: leftover}
  end

  defp publish_frame(%Frame{} = frame, %State{device_id: device_id, config: config} = state) do
    frame =
      frame
      |> Transform.transform_frame(config)
      |> then(&ClutterFilter.filter_frame(device_id, &1))

    envelope = {:radar_frame, device_id, frame}
    Phoenix.PubSub.broadcast(Octopus.PubSub, Radar.topic(), envelope)
    Phoenix.PubSub.broadcast(Octopus.PubSub, Radar.topic(device_id), envelope)

    state = cancel_watchdog(state)
    timer = Process.send_after(self(), :frame_watchdog, @frame_timeout_ms)

    %State{
      state
      | last_frame_at: System.monotonic_time(:millisecond),
        watchdog_timer: timer
    }
  end

  ## Logging

  defp set_status(%State{last_ui_status: prev, device_id: device_id} = state, status) do
    Radar.broadcast_status(device_id, status)

    if prev == status do
      state
    else
      state = %State{state | last_ui_status: status}
      log_status_transition(state, status)
      state
    end
  end

  defp log_status_transition(state, status) do
    case status do
      :working -> log(state, :info, "Online — streaming frames")
      :unavailable -> log(state, :info, "Unavailable — waiting for serial port")
      :stale -> log(state, :info, "Stale — recovering connection")
      :resetting -> log(state, :debug, "Resetting")
      _ -> :ok
    end
  end

  defp log(%State{device_id: id, port_name: port}, level, message) do
    Logger.log(level, "#{LogFormat.tag(id, port)} #{message}")
  end
end
