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
      phase are treated as ASCII ack lines, classified `AT+OK` / `Save Para
      Fail` per §8.3.
    * `:running` – feed every received chunk into `Octopus.Radar.Protocol`,
      publish each parsed frame.
  """

  use GenServer
  require Logger

  alias Circuits.UART
  alias Octopus.Radar
  alias Octopus.Radar.{Command, Frame, Protocol}

  @reopen_interval :timer.seconds(5)
  @ack_timeout :timer.seconds(2)

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
      :ack_timer
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

  defp via(device_id) do
    {:via, Registry, {Octopus.Radar.Registry, device_id}}
  end

  defp call_sensor(device_id, message) do
    try do
      GenServer.call(via(device_id), message)
    catch
      :exit, {:noproc, _} -> {:error, :no_sensor}
    end
  end

  ## GenServer callbacks

  @impl true
  def init(opts) do
    state = %State{
      device_id: Keyword.fetch!(opts, :device_id),
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
    {:ok, %State{state | uart: uart}, {:continue, :open_port}}
  end

  @impl true
  def handle_continue(:open_port, %State{} = state) do
    {:noreply, try_open(state)}
  end

  @impl true
  def handle_call({:set_sensitivity, level}, _from, %State{} = state) do
    log(state, :info, "Updating sensitivity to DPKTH=#{level} and re-initializing")
    new_config = Keyword.put(state.config, :sensitivity, level)
    {:reply, :ok, restart_init(%State{state | config: new_config})}
  end

  def handle_call(:reinitialize, _from, %State{} = state) do
    log(state, :info, "Re-initializing on operator request")
    {:reply, :ok, restart_init(state)}
  end

  @impl true
  def handle_info(:reopen_port, %State{} = state) do
    {:noreply, try_open(state)}
  end

  def handle_info(:ack_timeout, %State{phase: :configuring} = state) do
    log(state, :warning, "AT command timed out, resending: #{inspect(state.current_command)}")
    {:noreply, write_command(state.current_command, %State{state | ack_timer: nil})}
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
    _ = close_port(state)
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

        %State{
          state
          | phase: :configuring,
            pending_commands: Command.init_sequence(state.config),
            buffer: <<>>,
            ack_buffer: <<>>,
            last_track_count: nil
        }
        |> send_next_command()

      {:error, reason} ->
        log(state, :warning, "Could not open serial port: #{inspect(reason)} — retrying in 5s")
        schedule_reopen(state)
    end
  end

  defp schedule_reopen(%State{} = state) do
    Process.send_after(self(), :reopen_port, @reopen_interval)
    %State{state | phase: :opening, pending_commands: [], current_command: nil}
  end

  defp close_port(%State{uart: uart} = state) when is_pid(uart) do
    _ = UART.close(uart)
    cancel_ack_timer(state)
    %State{state | phase: :opening, buffer: <<>>, ack_buffer: <<>>, current_command: nil}
  end

  defp close_port(state), do: state

  ## Phase: configuring

  defp send_next_command(%State{pending_commands: []} = state) do
    log(state, :info, "Initialization complete — entering :running phase")
    %State{state | phase: :running, current_command: nil, ack_buffer: <<>>, buffer: <<>>}
  end

  defp send_next_command(%State{pending_commands: [cmd | rest]} = state) do
    write_command(cmd, %State{state | pending_commands: rest, current_command: cmd})
  end

  # Drop any in-flight ack timer + parser buffers, then re-issue the
  # full init sequence. Bytes that were already in flight from the
  # device (residual binary frames or text after AT+START) will arrive
  # while we're back in :configuring; the AT+OK matching simply ignores
  # anything that isn't a recognized response line, and the ack timeout
  # retries individual commands if needed, so the sequence always
  # converges.
  defp restart_init(%State{} = state) do
    state = cancel_ack_timer(state)

    %State{
      state
      | phase: :configuring,
        pending_commands: Command.init_sequence(state.config),
        current_command: nil,
        buffer: <<>>,
        ack_buffer: <<>>,
        last_track_count: nil
    }
    |> send_next_command()
  end

  defp write_command(cmd, %State{uart: uart} = state) do
    log(state, :info, "→ #{String.trim_trailing(cmd)}")
    :ok = UART.write(uart, cmd)
    arm_ack_timer(%State{state | current_command: cmd, ack_buffer: <<>>})
  end

  defp handle_ack_bytes(data, %State{ack_buffer: ack_buffer} = state) do
    # The radar ack stream is text; split on newline (handles \r\n by
    # stripping \r before classifying).
    chunks = String.split(ack_buffer <> data, "\n")
    {leftover, complete_lines} = List.pop_at(chunks, -1)

    Enum.reduce(complete_lines, %State{state | ack_buffer: leftover || <<>>}, fn line, acc ->
      apply_ack_line(String.trim(line), acc)
    end)
  end

  defp apply_ack_line("", state), do: state

  defp apply_ack_line(line, %State{} = state) do
    case Command.classify_response(line) do
      :ok ->
        log(state, :info, "← AT+OK")

        state
        |> cancel_ack_timer()
        |> send_next_command()

      :retry ->
        log(state, :warning, "← Save Para Fail — resending: #{inspect(state.current_command)}")

        state
        |> cancel_ack_timer()
        |> then(&write_command(state.current_command, &1))

      :other ->
        log(state, :debug, "← #{inspect(line)}")
        state
    end
  end

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

  defp publish_frame(%Frame{} = frame, %State{device_id: device_id} = state) do
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
