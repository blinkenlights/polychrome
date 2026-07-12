defmodule Octopus.Recording.Session do
  @moduledoc """
  Coordinates a recording session across the panel and radar recorders.

  A session records both streams into a single directory using **one shared
  clock**, so the panel video and the radar scope can be aligned frame-for-frame
  during playback:

      recordings/session-20260712-143000/
        panels.octorec
        radar.jsonl

  Both recorders are started with the same `started_at_ms` (wall clock) and
  `start_mono_ms` (monotonic origin), so their per-frame offsets share a common
  zero.

  Sessions always use file sinks (the record-then-encode workflow). For the
  advanced case of streaming a single stream to a remote server, drive
  `Octopus.Recording.PanelRecorder`/`RadarRecorder` directly with
  `sink_mod: Octopus.Recording.Sink.Remote`.

  This module owns auto-start on boot (when `enabled: true`) so that the shared
  clock applies to the auto-started session too.
  """

  use GenServer
  require Logger

  alias Octopus.Radar
  alias Octopus.Recording
  alias Octopus.Recording.{PanelRecorder, RadarRecorder, Sink}

  defmodule State do
    @moduledoc false
    defstruct active: false, dir: nil, panels: nil, radar: nil
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Start a recording session.

  Options:

    * `:dir` - base output directory (default: configured `output_dir`). A
      timestamped `session-<stamp>` subdirectory is created inside it.
    * `:panels` - record the panels (default `true`).
    * `:radar` - record radar (default: `Octopus.Radar.enabled?()`).

  Returns `{:ok, %{dir: dir, panels: target | nil, radar: target | nil}}`.
  """
  @spec start(keyword()) :: {:ok, map()} | {:error, term()}
  def start(opts \\ []) do
    GenServer.call(__MODULE__, {:start, opts})
  end

  @doc "Stop the current session, stopping both recorders."
  @spec stop() :: :ok | {:error, :not_recording}
  def stop do
    GenServer.call(__MODULE__, :stop)
  end

  @doc "Return the session status, including each recorder's status."
  @spec status() :: map()
  def status do
    GenServer.call(__MODULE__, :status)
  end

  ## Server callbacks

  @impl true
  def init(_opts) do
    {:ok, %State{}, {:continue, :maybe_autostart}}
  end

  @impl true
  def handle_continue(:maybe_autostart, %State{} = state) do
    if Recording.enabled?() do
      case do_start(state, []) do
        {:ok, new_state, info} ->
          Logger.info("[recording] Auto-started session -> #{info.dir}")
          {:noreply, new_state}

        {:error, reason} ->
          Logger.warning("[recording] Session auto-start failed: #{inspect(reason)}. Idle.")
          {:noreply, state}
      end
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_call({:start, _opts}, _from, %State{active: true} = state) do
    {:reply, {:error, :already_recording}, state}
  end

  def handle_call({:start, opts}, _from, %State{} = state) do
    case do_start(state, opts) do
      {:ok, new_state, info} -> {:reply, {:ok, info}, new_state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:stop, _from, %State{active: false} = state) do
    {:reply, {:error, :not_recording}, state}
  end

  def handle_call(:stop, _from, %State{}) do
    _ = PanelRecorder.stop_recording()
    _ = RadarRecorder.stop_recording()
    {:reply, :ok, %State{}}
  end

  def handle_call(:status, _from, %State{} = state) do
    info = %{
      active: state.active,
      dir: state.dir,
      panels: PanelRecorder.status(),
      radar: RadarRecorder.status()
    }

    {:reply, info, state}
  end

  ## Internal

  defp do_start(%State{} = _state, opts) do
    started_at_ms = System.system_time(:millisecond)
    start_mono_ms = System.monotonic_time(:millisecond)

    base_dir = Keyword.get(opts, :dir) || Recording.output_dir()
    dir = Path.join(base_dir, "session-#{stamp(started_at_ms)}")

    record_panels? = Keyword.get(opts, :panels, true)
    record_radar? = Keyword.get(opts, :radar, radar_enabled?())

    clock = [start_mono_ms: start_mono_ms, started_at_ms: started_at_ms]

    with {:ok, panel_target} <- maybe_start_panels(record_panels?, dir, clock),
         {:ok, radar_target} <- maybe_start_radar(record_radar?, dir, clock, panel_target) do
      info = %{dir: dir, panels: panel_target, radar: radar_target}
      {:ok, %State{active: true, dir: dir, panels: panel_target, radar: radar_target}, info}
    end
  end

  defp maybe_start_panels(false, _dir, _clock), do: {:ok, nil}

  defp maybe_start_panels(true, dir, clock) do
    opts = [sink_mod: Sink.File, sink_opts: [path: Path.join(dir, "panels.octorec")]] ++ clock
    PanelRecorder.start_recording(opts)
  end

  defp maybe_start_radar(false, _dir, _clock, _panel_target), do: {:ok, nil}

  defp maybe_start_radar(true, dir, clock, panel_target) do
    opts = [sink_mod: Sink.File, sink_opts: [path: Path.join(dir, "radar.jsonl")]] ++ clock

    case RadarRecorder.start_recording(opts) do
      {:ok, target} ->
        {:ok, target}

      {:error, reason} ->
        # Roll back the panel recorder so we never leave a half-started session.
        if panel_target, do: PanelRecorder.stop_recording()
        {:error, reason}
    end
  end

  defp radar_enabled? do
    Radar.enabled?()
  rescue
    _ -> false
  catch
    _, _ -> false
  end

  defp stamp(started_at_ms) do
    started_at_ms
    |> DateTime.from_unix!(:millisecond)
    |> Calendar.strftime("%Y%m%d-%H%M%S")
  end
end
