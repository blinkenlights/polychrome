defmodule Octopus.Recording.PanelRecorder do
  @moduledoc """
  Records the frames the mixer sends to the LED panels into an append-only
  recording stream (see `Octopus.Recording.Format`).

  ## Safety

  This recorder is designed so it can never crash or influence the running
  installation:

    * It is a passive `Phoenix.PubSub` subscriber of the mixer's frame topic.
      Broadcasts are asynchronous and fire-and-forget, so the mixer and
      broadcaster never wait for, or are affected by, the recorder.
    * It only subscribes while actively recording, so when disabled there is
      zero message traffic and zero overhead.
    * Every incoming frame is processed inside a `try/rescue/catch`; a bad
      frame or a sink error degrades to a dropped frame (and, for sink errors,
      a clean stop), never a crash.
    * It guards its own mailbox: if messages pile up faster than they can be
      written (slow disk / slow remote sink) it drops frames instead of growing
      memory without bound.
    * It lives in an isolated supervision subtree, so even an unexpected crash
      only restarts the recorder.

  ## Tap point

  Subscribes to `Octopus.Mixer` and records `{:mixer, {:frame, frame}}`
  messages. These carry the logical, full-resolution frame *before* hardware
  de-tangling and UDP splitting, i.e. exactly what should be visualized.

  The same frame is broadcast once per UDP split part, so identical frames that
  arrive within `#{5}` ms of each other are de-duplicated; dropped duplicates
  simply extend the previous frame's on-screen duration in playback.
  """

  use GenServer
  require Logger

  alias Octopus.Installation
  alias Octopus.Recording
  alias Octopus.Recording.{Format, Sink}
  alias Octopus.Protobuf.{RGBFrame, WFrame}

  @dedup_window_ms 5

  defmodule State do
    @moduledoc false
    defstruct active: false,
              sink_mod: nil,
              sink: nil,
              path: nil,
              start_mono_ms: nil,
              started_at_ms: nil,
              num_panels: nil,
              panel_width: nil,
              panel_height: nil,
              frame_bytes: nil,
              w_bytes: nil,
              max_queue: 600,
              last_rgb: nil,
              last_offset_ms: nil,
              written: 0,
              dropped: 0
  end

  ## Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Start a recording.

  Options:

    * `:sink_mod` - module implementing `Octopus.Recording.Sink`
      (default `Octopus.Recording.Sink.File`).
    * `:sink_opts` - options passed to the sink's `open/1`. For the file sink
      a `:path` is used; when omitted a timestamped path under the configured
      output directory is generated.
    * `:dir` - convenience for the file sink: output directory for the
      generated filename.
  """
  @spec start_recording(keyword()) :: {:ok, String.t()} | {:error, term()}
  def start_recording(opts \\ []) do
    GenServer.call(__MODULE__, {:start_recording, opts})
  end

  @doc "Stop the current recording, flushing and closing the sink."
  @spec stop_recording() :: :ok | {:error, :not_recording}
  def stop_recording do
    GenServer.call(__MODULE__, :stop_recording)
  end

  @doc "Return a status map describing the recorder."
  @spec status() :: map()
  def status do
    GenServer.call(__MODULE__, :status)
  end

  ## Server callbacks

  @impl true
  def init(_opts) do
    # Autostart is coordinated by Octopus.Recording.Session so the panel and
    # radar recorders share one clock; this recorder just idles until told to
    # start.
    {:ok, %State{max_queue: Recording.max_queue()}}
  end

  @impl true
  def handle_call({:start_recording, opts}, _from, %State{active: true} = state) do
    _ = opts
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
  def handle_info({:mixer, {:frame, frame}}, %State{active: true} = state) do
    {:noreply, maybe_record(frame, state)}
  end

  # Ignore all other mixer traffic (config changes, and frames while inactive).
  def handle_info({:mixer, _}, %State{} = state), do: {:noreply, state}
  def handle_info(_msg, %State{} = state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %State{active: true} = state) do
    _ = do_stop(state)
    :ok
  end

  def terminate(_reason, _state), do: :ok

  ## Recording lifecycle

  defp do_start(%State{} = state, opts) do
    num_panels = Installation.num_panels()
    panel_width = Installation.panel_width()
    panel_height = Installation.panel_height()

    started_at_ms = Keyword.get(opts, :started_at_ms) || System.system_time(:millisecond)
    start_mono_ms = Keyword.get(opts, :start_mono_ms) || System.monotonic_time(:millisecond)
    {sink_mod, sink_opts} = resolve_sink(opts, started_at_ms)

    with {:ok, sink} <- sink_mod.open(sink_opts),
         header = Format.header(num_panels, panel_width, panel_height, started_at_ms),
         {:ok, sink} <- sink_mod.write(sink, header) do
      Octopus.Mixer.subscribe()

      state = %State{
        state
        | active: true,
          sink_mod: sink_mod,
          sink: sink,
          path: sink_mod.describe(sink),
          start_mono_ms: start_mono_ms,
          started_at_ms: started_at_ms,
          num_panels: num_panels,
          panel_width: panel_width,
          panel_height: panel_height,
          frame_bytes: Format.frame_bytes(num_panels, panel_width, panel_height),
          w_bytes: num_panels * panel_width * panel_height,
          last_rgb: nil,
          last_offset_ms: nil,
          written: 0,
          dropped: 0
      }

      {:ok, state, sink_mod.describe(sink)}
    end
  rescue
    error -> {:error, error}
  end

  defp do_stop(%State{sink_mod: sink_mod, sink: sink} = state) do
    Octopus.Mixer.unsubscribe()

    if sink_mod && sink do
      _ = safe_close(sink_mod, sink)
    end

    Logger.info(
      "[recording] Stopped panel recording (#{state.written} frames written, #{state.dropped} dropped)"
    )

    %State{max_queue: state.max_queue}
  end

  # Resolve which sink to use and the options to open it with. An explicit
  # `:sink_mod` in the start options wins; otherwise the configured `:sink`
  # spec is used (defaulting to a file sink).
  defp resolve_sink(opts, started_at_ms) do
    case Keyword.fetch(opts, :sink_mod) do
      {:ok, Sink.File} ->
        {Sink.File, file_open_opts(opts, [], started_at_ms)}

      {:ok, mod} ->
        {mod, Keyword.get(opts, :sink_opts, [])}

      :error ->
        case Recording.sink_spec() do
          {:remote, remote_opts} ->
            {Sink.Remote, remote_opts}

          {:file, file_opts} ->
            {Sink.File, file_open_opts(opts, file_opts, started_at_ms)}

          _ ->
            {Sink.File, file_open_opts(opts, [], started_at_ms)}
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

    "panels-#{stamp}.octorec"
  end

  ## Frame handling

  defp maybe_record(frame, %State{} = state) do
    if overloaded?(state) do
      %State{state | dropped: state.dropped + 1}
    else
      record_frame(frame, state)
    end
  rescue
    error ->
      Logger.warning("[recording] Dropping frame after error: #{inspect(error)}")
      %State{state | dropped: state.dropped + 1}
  catch
    kind, reason ->
      Logger.warning("[recording] Dropping frame after #{kind}: #{inspect(reason)}")
      %State{state | dropped: state.dropped + 1}
  end

  defp overloaded?(%State{max_queue: max}) do
    case Process.info(self(), :message_queue_len) do
      {:message_queue_len, len} -> len > max
      _ -> false
    end
  end

  defp record_frame(frame, %State{} = state) do
    with {:ok, data} <- frame_data(frame),
         {:ok, rgb} <- Format.normalize(data, state.frame_bytes, state.w_bytes) do
      offset_ms = max(System.monotonic_time(:millisecond) - state.start_mono_ms, 0)

      if duplicate?(state, rgb, offset_ms) do
        state
      else
        write_record(state, offset_ms, rgb)
      end
    else
      _ -> %State{state | dropped: state.dropped + 1}
    end
  end

  defp frame_data(%RGBFrame{data: data}) when is_binary(data), do: {:ok, data}
  defp frame_data(%WFrame{data: data}) when is_binary(data), do: {:ok, data}
  defp frame_data(%{data: data}) when is_binary(data), do: {:ok, data}
  defp frame_data(_), do: :error

  defp duplicate?(%State{last_rgb: last, last_offset_ms: last_offset}, rgb, offset_ms)
       when is_binary(last) and is_integer(last_offset) do
    offset_ms - last_offset < @dedup_window_ms and rgb == last
  end

  defp duplicate?(_state, _rgb, _offset_ms), do: false

  defp write_record(%State{sink_mod: sink_mod, sink: sink} = state, offset_ms, rgb) do
    record = Format.record(offset_ms, rgb)

    case sink_mod.write(sink, record) do
      {:ok, sink} ->
        %State{
          state
          | sink: sink,
            last_rgb: rgb,
            last_offset_ms: offset_ms,
            written: state.written + 1
        }

      {:error, reason} ->
        Logger.error("[recording] Sink write failed: #{inspect(reason)}. Stopping recording.")
        do_stop(state)
    end
  end

  defp safe_close(sink_mod, sink) do
    sink_mod.close(sink)
  rescue
    error -> Logger.warning("[recording] Sink close error: #{inspect(error)}")
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
      started_at_ms: state.started_at_ms,
      num_panels: state.num_panels,
      panel_width: state.panel_width,
      panel_height: state.panel_height,
      frame_bytes: state.frame_bytes
    }
  end
end
