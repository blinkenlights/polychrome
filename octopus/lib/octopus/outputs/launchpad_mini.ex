defmodule Octopus.Outputs.LaunchpadMini do
  @moduledoc """
  Mirrors `Octopus.Mixer` RGB frames onto a Novation Launchpad Mini MK3 connected
  via USB-MIDI, using it as an optional 8x8 colour output.

  This process is intentionally **page-scoped**: it's started (linked) by
  `OctopusWeb.LaunchpadLive` on mount and stops when the LiveView unmounts. It is
  not part of the application's supervision tree, since the Launchpad is an
  optional debug/output device, not a permanent installation component.

  Only meaningful for installations with `Installation.num_panels() == 1` and
  `Installation.panel_layout() == {8, 8}` (e.g. Pixie).

  See the SysEx protocol details in
  `docs/novation_launchpad_mk3_mini_-_programmers_reference_manual.pdf`.
  """

  use GenServer
  require Logger

  alias Octopus.{Installation, Mixer}
  alias Octopus.Protobuf.RGBFrame

  @sysex_header [0xF0, 0x00, 0x20, 0x29, 0x02, 0x0D]
  @sysex_footer 0xF7

  @cmd_led_lighting 0x03
  @cmd_brightness 0x08
  @cmd_programmer_mode 0x0E

  @lighting_type_rgb 0x03

  # Name substring identifying the Launchpad's "MIDI In/Out" interface (used
  # for Programmer mode / lighting), as opposed to its "DAW In/Out" interface.
  @midi_interface_name_part "MIDI"
  @daw_interface_name_part "DAW"
  @device_name_part "LPMiniMK3"

  # Drop frames arriving faster than this to avoid flooding the USB-MIDI link.
  @min_frame_interval_ms 33

  defmodule State do
    @moduledoc false
    defstruct [:out_conn, :last_sent_at_ms, frames_sent: 0]
  end

  ## Public API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Sets the LED brightness (0-127) on the connected Launchpad, if any.
  No-ops silently if the process isn't running or no device is connected.
  """
  @spec set_brightness(non_neg_integer()) :: :ok
  def set_brightness(value) when is_integer(value) and value >= 0 and value <= 127 do
    case GenServer.whereis(__MODULE__) do
      nil -> :ok
      pid -> GenServer.cast(pid, {:set_brightness, value})
    end
  end

  @doc """
  Returns the current connection status.
  """
  @spec status() :: :not_running | :connected | {:error, term()}
  def status do
    case GenServer.whereis(__MODULE__) do
      nil -> :not_running
      pid -> GenServer.call(pid, :status)
    end
  end

  ## GenServer callbacks

  @impl true
  def init(_opts) do
    case find_and_open_port() do
      {:ok, out_conn} ->
        Logger.info("Launchpad Mini: connected via #{inspect(out_conn.name)}")

        send_sysex(out_conn, [@cmd_programmer_mode, 0x01])
        send_sysex(out_conn, [@cmd_brightness, Octopus.Params.Launchpad.brightness()])

        Mixer.subscribe()

        # `System.monotonic_time/1` has no fixed epoch (it's frequently a large
        # negative number), so the initial "last sent" timestamp must be
        # derived from it too — seeding this with `0` would make the very
        # first frame-rate check compare against the wrong reference point
        # and could suppress every frame indefinitely.
        initial_last_sent_at_ms = System.monotonic_time(:millisecond) - @min_frame_interval_ms

        {:ok, %State{out_conn: out_conn, last_sent_at_ms: initial_last_sent_at_ms}}

      {:error, reason} = error ->
        Logger.warning("Launchpad Mini: could not connect (#{inspect(reason)})")
        {:stop, error}
    end
  end

  @impl true
  def handle_call(:status, _from, %State{out_conn: nil} = state) do
    {:reply, {:error, :not_connected}, state}
  end

  def handle_call(:status, _from, %State{} = state) do
    {:reply, :connected, state}
  end

  @impl true
  def handle_cast({:set_brightness, value}, %State{out_conn: out_conn} = state) do
    send_sysex(out_conn, [@cmd_brightness, value])
    {:noreply, state}
  end

  @impl true
  def handle_info({:mixer, {:frame, %RGBFrame{} = frame}}, %State{} = state) do
    if compatible_installation?() do
      {:noreply, maybe_send_frame(frame, state)}
    else
      {:noreply, state}
    end
  end

  def handle_info({:mixer, _msg}, %State{} = state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %State{out_conn: nil}), do: :ok

  def terminate(_reason, %State{out_conn: out_conn}) do
    send_sysex(out_conn, [@cmd_programmer_mode, 0x00])
    Midiex.close(out_conn)
    :ok
  end

  ## Internal helpers

  defp compatible_installation? do
    Installation.num_panels() == 1 and Installation.panel_layout() == {8, 8}
  end

  defp find_and_open_port do
    case Midiex.ports(:output) |> Enum.find(&launchpad_midi_port?/1) do
      nil -> {:error, :not_found}
      port -> {:ok, Midiex.open(port)}
    end
  rescue
    error -> {:error, error}
  end

  defp launchpad_midi_port?(%Midiex.MidiPort{name: name}) do
    String.contains?(name, @device_name_part) and
      String.contains?(name, @midi_interface_name_part) and
      not String.contains?(name, @daw_interface_name_part)
  end

  # Frame counter logging is intentionally chatty at :info for the very first
  # frame (so `wie finde ich heraus, ob Daten gesendet werden?` has an obvious
  # answer in the logs) and then drops to a low-frequency :debug heartbeat.
  @frame_log_every 300

  defp maybe_send_frame(%RGBFrame{} = frame, %State{last_sent_at_ms: last_sent_at_ms} = state) do
    now_ms = System.monotonic_time(:millisecond)

    if now_ms - last_sent_at_ms >= @min_frame_interval_ms do
      send_sysex(state.out_conn, [@cmd_led_lighting | colourspecs(frame)])
      frames_sent = state.frames_sent + 1
      log_frame_sent(frames_sent)
      %State{state | last_sent_at_ms: now_ms, frames_sent: frames_sent}
    else
      state
    end
  end

  defp log_frame_sent(1), do: Logger.info("Launchpad Mini: sending frames (first frame sent)")

  defp log_frame_sent(count) when rem(count, @frame_log_every) == 0,
    do: Logger.debug("Launchpad Mini: #{count} frames sent so far")

  defp log_frame_sent(_count), do: :ok

  # Builds one `<<type, pad_index, r, g, b>>` colourspec per pixel, for the
  # LED lighting SysEx message (RGB type). Pixel data is laid out row-major
  # (y then x, top row first), matching `Octopus.Mixer`'s frame construction.
  defp colourspecs(%RGBFrame{data: data}) do
    for <<r::8, g::8, b::8 <- data>>, reduce: {[], 0} do
      {acc, index} ->
        {[colourspec(index, r, g, b) | acc], index + 1}
    end
    |> elem(0)
    |> Enum.reverse()
    |> List.flatten()
  end

  defp colourspec(index, r, g, b) do
    x = rem(index, 8)
    y = div(index, 8)

    [@lighting_type_rgb, pad_index(x, y), to_7bit(r), to_7bit(g), to_7bit(b)]
  end

  # Programmer-mode pad numbering: row 1 = bottom row, row 8 = top row;
  # column 1 = leftmost. `y` is the canvas row (0 = top), `x` the canvas
  # column (0 = leftmost). Validated against the three worked examples in the
  # programmer's reference manual (lower-left = 11, upper-left = 81,
  # lower-right = 18).
  defp pad_index(x, y), do: 10 * (8 - y) + (x + 1)

  defp to_7bit(value) when is_integer(value), do: value |> Bitwise.bsr(1) |> min(127)

  defp send_sysex(out_conn, body) do
    Midiex.send_msg(out_conn, IO.iodata_to_binary(@sysex_header ++ body ++ [@sysex_footer]))
  end
end
