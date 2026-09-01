defmodule Octopus.Sound.Engine.SuperCollider do
  @moduledoc """
  Backend for SuperCollider's synthesis server, `scsynth`.

  Elixir takes the role `sclang` would otherwise have: it holds the state and
  decides what happens when, and talks to the server over OSC. Notes are sent
  as bundles carrying a timetag, so the server executes them sample accurate
  at the intended moment and jitter in the BEAM never reaches the audio.

  In development the server is started as a port of this process, so `iex -S
  mix phx.server` is all that is needed. In the installation it is expected to
  be a system service and `auto_start: false` is the sane setting.

  Sounds come from SynthDefs in `priv/synthdefs`, built by `mix sound.synthdefs`.
  """

  use GenServer

  @behaviour Octopus.Sound.Engine

  require Logger

  alias Octopus.Sound.{Engine, OSC, Time}

  @default_host {127, 0, 0, 1}
  @default_port 57_110
  @first_node_id 1000
  @last_node_id 100_000
  # macOS app bundle — Linux installs put both binaries on the PATH.
  @macos_bundle "/Applications/SuperCollider.app/Contents"

  # -- Engine ---------------------------------------------------------------

  @impl Octopus.Sound.Engine
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl Octopus.Sound.Engine
  def capabilities do
    %{scheduling: :timestamped, channels: Engine.channels()}
  end

  @impl Octopus.Sound.Engine
  def note(params), do: GenServer.cast(__MODULE__, {:note, params})

  @impl Octopus.Sound.Engine
  def voice(id, params), do: GenServer.cast(__MODULE__, {:voice, id, params})

  @impl Octopus.Sound.Engine
  def set_voice(id, params), do: GenServer.cast(__MODULE__, {:set_voice, id, params})

  @impl Octopus.Sound.Engine
  def release(id), do: GenServer.cast(__MODULE__, {:release, id})

  @impl Octopus.Sound.Engine
  def panic, do: GenServer.cast(__MODULE__, :panic)

  @doc "Path of the `scsynth` binary, or `nil` when SuperCollider is not installed."
  @spec scsynth_path() :: binary() | nil
  def scsynth_path do
    System.find_executable("scsynth") || existing(Path.join(@macos_bundle, "Resources/scsynth"))
  end

  # -- Server ---------------------------------------------------------------

  @impl GenServer
  def init(opts) do
    Process.flag(:trap_exit, true)

    config = Keyword.merge(Keyword.get(Engine.config(), :super_collider, []), opts)
    port = Keyword.get(config, :port, @default_port)
    channels = Keyword.get(config, :output_channels) || Engine.channels()

    state = %{
      host: Keyword.get(config, :host, @default_host),
      port: port,
      channels: channels,
      mapping: Keyword.get(config, :mapping, :direct),
      socket: nil,
      os_port: nil,
      defs_loaded?: false,
      # Sustained voices need their node id kept, so they can be changed and
      # let go later. One-shot notes free themselves and are forgotten.
      voices: %{}
    }

    {:ok, state, {:continue, {:boot, Keyword.get(config, :auto_start, false)}}}
  end

  @impl GenServer
  def handle_continue({:boot, auto_start?}, state) do
    {:ok, socket} = :gen_udp.open(0, [:binary, active: true])
    state = %{state | socket: socket}

    # A server may already be running — started by hand, or left over from a
    # previous run. Adopting it beats spawning a second one that would fail on
    # the port and take the audio device with it.
    state =
      if auto_start? and not server_running?(state) do
        %{state | os_port: start_server(state)}
      else
        state
      end

    # The server answers /status once it is up; that reply is the cue to load
    # the SynthDefs. Asking repeatedly costs nothing and survives a restart of
    # a server we do not own.
    {:ok, _} = :timer.send_interval(1_000, :probe)
    send(self(), :probe)

    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:note, params}, state) do
    %{channel: channel, note: note, velocity: velocity, duration_ms: duration, at_ms: at_ms} =
      params

    message =
      OSC.message("/s_new", [
        Map.get(params, :synth, "pc_ping"),
        next_node_id(),
        0,
        0,
        "out",
        output_bus(channel, state) / 1,
        "freq",
        Engine.frequency(note),
        "amp",
        velocity / 1,
        "dur",
        duration / 1000
      ])

    send_at(state, [message], at_ms)
    {:noreply, state}
  end

  def handle_cast({:voice, id, params}, state) do
    state = release_voice(state, id)
    node_id = next_node_id()

    message =
      OSC.message("/s_new", [
        Map.get(params, :synth, "pc_voice"),
        node_id,
        0,
        0,
        "out",
        output_bus(params.channel, state) / 1,
        "freq",
        Engine.frequency(params.note),
        "amp",
        params.amp / 1,
        "cutoff",
        Map.get(params, :cutoff, 2000) / 1
      ])

    send_now(state, [message])
    {:noreply, %{state | voices: Map.put(state.voices, id, node_id)}}
  end

  def handle_cast({:set_voice, id, params}, state) do
    case Map.fetch(state.voices, id) do
      {:ok, node_id} ->
        send_now(state, [OSC.message("/n_set", [node_id] ++ controls(params))])

      :error ->
        :ok
    end

    {:noreply, state}
  end

  def handle_cast({:release, id}, state) do
    {:noreply, release_voice(state, id)}
  end

  def handle_cast(:panic, state) do
    send_now(state, [OSC.message("/clearSched"), OSC.message("/g_freeAll", [0])])
    {:noreply, %{state | voices: %{}}}
  end

  @impl GenServer
  def handle_info(:probe, %{defs_loaded?: true} = state), do: {:noreply, state}

  def handle_info(:probe, state) do
    send_now(state, [OSC.message("/status")])
    {:noreply, state}
  end

  def handle_info({:udp, _socket, _ip, _port, data}, state) do
    {:noreply, handle_reply(address(data), state)}
  end

  def handle_info({os_port, {:data, data}}, %{os_port: os_port} = state) do
    data |> String.trim() |> log_server_output()
    {:noreply, state}
  end

  def handle_info({os_port, {:exit_status, status}}, %{os_port: os_port} = state) do
    Logger.error("[sound] scsynth exited with status #{status}")
    {:noreply, %{state | os_port: nil, defs_loaded?: false}}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_reason, %{os_port: os_port} = state) when is_port(os_port) do
    # Closing the port only closes the pipes; scsynth would keep running and
    # hold both the UDP port and the audio device. /quit shuts it down.
    send_now(state, [OSC.message("/quit")])
    Process.sleep(100)
    Port.close(os_port)
  catch
    :error, :badarg -> :ok
  end

  def terminate(_reason, _state), do: :ok

  # -- Internals ------------------------------------------------------------

  defp handle_reply("/status.reply", %{defs_loaded?: false} = state) do
    directory = Application.app_dir(:octopus, "priv/synthdefs")

    if File.dir?(directory) and File.ls!(directory) != [] do
      Logger.info("[sound] scsynth is up, loading SynthDefs from #{directory}")
      send_now(state, [OSC.message("/d_loadDir", [directory])])
      %{state | defs_loaded?: true}
    else
      Logger.warning("[sound] no SynthDefs in #{directory} — run `mix sound.synthdefs`")
      state
    end
  end

  defp handle_reply("/fail", state) do
    Logger.warning("[sound] scsynth reported a failure")
    state
  end

  defp handle_reply(_address, state), do: state

  # Gate 0 lets the envelope release; the synth frees its own node afterwards.
  defp release_voice(state, id) do
    case Map.pop(state.voices, id) do
      {nil, _voices} ->
        state

      {node_id, voices} ->
        send_now(state, [OSC.message("/n_set", [node_id, "gate", 0.0])])
        %{state | voices: voices}
    end
  end

  defp controls(params) do
    params
    |> Map.take([:amp, :cutoff, :freq])
    |> Enum.flat_map(fn {key, value} -> [to_string(key), value / 1] end)
  end

  # A ring of twelve panels on a stereo laptop would leave ten of them
  # inaudible. Folding wraps them onto the outputs that exist, so movement
  # around the ring is still audible while prototyping — the installation
  # itself runs `:direct`, one output per panel.
  # Contiguous arcs, not modulo: with two outputs, panels 1..6 go left and
  # 7..12 right, so a pattern that moves around the ring still moves across
  # the speakers. Modulo would put panel 1 and panel 7 — opposite each other —
  # on the same side.
  defp output_bus(channel, %{mapping: :fold, channels: channels}) do
    div((channel - 1) * channels, Engine.panels())
  end

  defp output_bus(channel, _state), do: channel - 1

  defp send_at(state, messages, at_ms) do
    if at_ms - Time.now() > 1 do
      send_packet(state, OSC.bundle_at(messages, Time.to_unix(at_ms)))
    else
      send_now(state, messages)
    end
  end

  defp send_now(state, messages), do: send_packet(state, OSC.bundle(messages))

  # Blocking on purpose: nothing else talks to this process during boot, and
  # the answer decides whether we spawn a server at all.
  defp server_running?(state) do
    send_now(state, [OSC.message("/status")])

    receive do
      {:udp, _socket, _ip, _port, data} -> address(data) == "/status.reply"
    after
      250 -> false
    end
  end

  defp send_packet(%{socket: nil}, _packet), do: :ok

  defp send_packet(%{socket: socket, host: host, port: port}, packet) do
    :gen_udp.send(socket, host, port, packet)
  end

  defp start_server(%{port: port, channels: channels}) do
    case scsynth_path() do
      nil ->
        Logger.error("[sound] scsynth not found — start it yourself or install SuperCollider")
        nil

      path ->
        args = ["-u", to_string(port), "-i", "0", "-o", to_string(channels)] ++ plugin_args()
        Logger.info("[sound] starting scsynth: #{path} #{Enum.join(args, " ")}")

        Port.open({:spawn_executable, path}, [
          :binary,
          :exit_status,
          :stderr_to_stdout,
          args: args
        ])
    end
  end

  defp plugin_args do
    case existing(Path.join(@macos_bundle, "Resources/plugins")) do
      nil -> []
      plugins -> ["-U", plugins]
    end
  end

  # Node ids only have to be unique among live nodes; every synth frees itself
  # when its envelope ends, so a plain counter is enough.
  defp next_node_id do
    :counters.get(counter(), 1)
    |> case do
      id when id >= @last_node_id -> :counters.put(counter(), 1, @first_node_id)
      _ -> :ok
    end

    :counters.add(counter(), 1, 1)
    :counters.get(counter(), 1)
  end

  defp counter do
    case :persistent_term.get({__MODULE__, :node_ids}, nil) do
      nil ->
        counter = :counters.new(1, [:atomics])
        :counters.put(counter, 1, @first_node_id)
        :persistent_term.put({__MODULE__, :node_ids}, counter)
        counter

      counter ->
        counter
    end
  end

  defp address(<<"#bundle", 0, _timetag::binary-size(8), _size::size(32), rest::binary>>),
    do: address(rest)

  defp address(data) do
    case :binary.split(data, <<0>>) do
      [address | _] -> address
      _ -> ""
    end
  end

  defp existing(path), do: if(File.exists?(path), do: path)

  defp log_server_output(""), do: :ok
  defp log_server_output(output), do: Logger.info("[scsynth] #{output}")
end
