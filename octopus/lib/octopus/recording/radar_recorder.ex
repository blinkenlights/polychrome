defmodule Octopus.Recording.RadarRecorder do
  @moduledoc """
  Records radar tracking frames into a JSONL recording
  (`Octopus.Recording.RadarFormat`).

  Subscribes to `Octopus.Radar` and records every `{:radar_frame, device_id,
  frame}` message. Positions are already in the installation global frame, so
  all sensors are recorded into a single, mergeable stream.

  ## Safety

  Uses the same guarantees as `Octopus.Recording.PanelRecorder`: it is a passive
  PubSub subscriber (never blocks the radar sensors), only subscribes while
  recording, processes every frame inside `try/rescue/catch`, guards its mailbox
  and drops frames on overload, and lives in an isolated supervision subtree.

  ## Shared timeline

  Frame timestamps are `frame.received_at - start_mono_ms` (both monotonic
  milliseconds). When started with the same `:start_mono_ms`/`:started_at_ms`
  as the panel recorder (as `Octopus.Recording.Session` does), radar and panel
  recordings share one timeline and can be aligned during playback.
  """

  use GenServer
  require Logger

  alias Octopus.Radar
  alias Octopus.Radar.Frame
  alias Octopus.Recording
  alias Octopus.Recording.{RadarFormat, Sink}

  defmodule State do
    @moduledoc false
    defstruct active: false,
              sink_mod: nil,
              sink: nil,
              path: nil,
              start_mono_ms: nil,
              started_at_ms: nil,
              max_queue: 600,
              written: 0,
              dropped: 0
  end

  ## Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Start a radar recording.

  Options mirror `Octopus.Recording.PanelRecorder.start_recording/1`:
  `:sink_mod`, `:sink_opts`, `:dir`, plus optional shared clock
  `:start_mono_ms` and `:started_at_ms`.
  """
  @spec start_recording(keyword()) :: {:ok, String.t()} | {:error, term()}
  def start_recording(opts \\ []) do
    GenServer.call(__MODULE__, {:start_recording, opts})
  end

  @doc "Stop the current radar recording."
  @spec stop_recording() :: :ok | {:error, :not_recording}
  def stop_recording do
    GenServer.call(__MODULE__, :stop_recording)
  end

  @doc "Return a status map describing the radar recorder."
  @spec status() :: map()
  def status do
    GenServer.call(__MODULE__, :status)
  end

  ## Server callbacks

  @impl true
  def init(_opts) do
    {:ok, %State{max_queue: Recording.max_queue()}}
  end

  @impl true
  def handle_call({:start_recording, _opts}, _from, %State{active: true} = state) do
    {:reply, {:error, :already_recording}, state}
  end

  def handle_call({:start_recording, opts}, _from, %State{} = state) do
    case do_start(state, opts) do
      {:ok, new_state, path} -> {:reply, {:ok, path}, new_state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:stop_recording, _from, %State{active: false} = state) do
    {:reply, {:error, :not_recording}, state}
  end

  def handle_call(:stop_recording, _from, %State{} = state) do
    {:reply, :ok, do_stop(state)}
  end

  def handle_call(:status, _from, %State{} = state) do
    {:reply, status_map(state), state}
  end

  @impl true
  def handle_info({:radar_frame, device_id, %Frame{} = frame}, %State{active: true} = state) do
    {:noreply, maybe_record(device_id, frame, state)}
  end

  def handle_info(_msg, %State{} = state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %State{active: true} = state) do
    _ = do_stop(state)
    :ok
  end

  def terminate(_reason, _state), do: :ok

  ## Recording lifecycle

  defp do_start(%State{} = state, opts) do
    started_at_ms = Keyword.get(opts, :started_at_ms) || System.system_time(:millisecond)
    start_mono_ms = Keyword.get(opts, :start_mono_ms) || System.monotonic_time(:millisecond)
    {sink_mod, sink_opts} = resolve_sink(opts, started_at_ms)

    with {:ok, sink} <- sink_mod.open(sink_opts),
         meta = RadarFormat.meta_line(started_at_ms, world_radius_m()),
         {:ok, sink} <- sink_mod.write(sink, meta) do
      Radar.subscribe()

      state = %State{
        state
        | active: true,
          sink_mod: sink_mod,
          sink: sink,
          path: sink_mod.describe(sink),
          start_mono_ms: start_mono_ms,
          started_at_ms: started_at_ms,
          written: 0,
          dropped: 0
      }

      {:ok, state, sink_mod.describe(sink)}
    end
  rescue
    error -> {:error, error}
  end

  defp do_stop(%State{sink_mod: sink_mod, sink: sink} = state) do
    _ = Phoenix.PubSub.unsubscribe(Octopus.PubSub, Radar.topic())

    if sink_mod && sink do
      _ = safe_close(sink_mod, sink)
    end

    Logger.info(
      "[recording] Stopped radar recording (#{state.written} frames written, #{state.dropped} dropped)"
    )

    %State{max_queue: state.max_queue}
  end

  defp world_radius_m do
    Radar.world_radius_m()
  rescue
    _ -> 8.0
  catch
    _, _ -> 8.0
  end

  defp resolve_sink(opts, started_at_ms) do
    case Keyword.fetch(opts, :sink_mod) do
      {:ok, Sink.File} ->
        {Sink.File, file_open_opts(opts, [], started_at_ms)}

      {:ok, mod} ->
        {mod, Keyword.get(opts, :sink_opts, [])}

      :error ->
        case Recording.sink_spec() do
          {:remote, remote_opts} -> {Sink.Remote, remote_opts}
          {:file, file_opts} -> {Sink.File, file_open_opts(opts, file_opts, started_at_ms)}
          _ -> {Sink.File, file_open_opts(opts, [], started_at_ms)}
        end
    end
  end

  defp file_open_opts(opts, file_opts, started_at_ms) do
    sink_opts = Keyword.get(opts, :sink_opts, [])

    path =
      cond do
        p = Keyword.get(sink_opts, :path) -> p
        p = Keyword.get(file_opts, :path) -> p
        true -> Path.join(file_dir(opts, file_opts), generated_filename(started_at_ms))
      end

    [path: path]
  end

  defp file_dir(opts, file_opts) do
    Keyword.get(opts, :dir) || Keyword.get(file_opts, :dir) || Recording.output_dir()
  end

  defp generated_filename(started_at_ms) do
    stamp =
      started_at_ms
      |> DateTime.from_unix!(:millisecond)
      |> Calendar.strftime("%Y%m%d-%H%M%S")

    "radar-#{stamp}.jsonl"
  end

  ## Frame handling

  defp maybe_record(device_id, frame, %State{} = state) do
    if overloaded?(state) do
      %State{state | dropped: state.dropped + 1}
    else
      record_frame(device_id, frame, state)
    end
  rescue
    error ->
      Logger.warning("[recording] Dropping radar frame after error: #{inspect(error)}")
      %State{state | dropped: state.dropped + 1}
  catch
    kind, reason ->
      Logger.warning("[recording] Dropping radar frame after #{kind}: #{inspect(reason)}")
      %State{state | dropped: state.dropped + 1}
  end

  defp overloaded?(%State{max_queue: max}) do
    case Process.info(self(), :message_queue_len) do
      {:message_queue_len, len} -> len > max
      _ -> false
    end
  end

  defp record_frame(device_id, %Frame{} = frame, %State{} = state) do
    offset_ms = max(frame_time(frame) - state.start_mono_ms, 0)
    line = RadarFormat.frame_line(offset_ms, device_id, frame.frame_number, frame.tracks)

    case state.sink_mod.write(state.sink, line) do
      {:ok, sink} ->
        %State{state | sink: sink, written: state.written + 1}

      {:error, reason} ->
        Logger.error("[recording] Radar sink write failed: #{inspect(reason)}. Stopping.")
        do_stop(state)
    end
  end

  defp frame_time(%Frame{received_at: received_at}) when is_integer(received_at), do: received_at
  defp frame_time(_frame), do: System.monotonic_time(:millisecond)

  defp safe_close(sink_mod, sink) do
    sink_mod.close(sink)
  rescue
    error -> Logger.warning("[recording] Radar sink close error: #{inspect(error)}")
  end

  defp status_map(%State{active: false} = state) do
    %{active: false, written: state.written, dropped: state.dropped}
  end

  defp status_map(%State{} = state) do
    %{
      active: true,
      sink: state.path,
      written: state.written,
      dropped: state.dropped,
      started_at_ms: state.started_at_ms
    }
  end
end
