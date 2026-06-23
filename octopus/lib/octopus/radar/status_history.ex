defmodule Octopus.Radar.StatusHistory do
  @moduledoc """
  Persistent history of sensor status transitions for the last 60 seconds.

  Subscribes to the per-sensor status PubSub topics as soon as the
  supervisor starts it and records every `{wall_clock_ms, status}` event
  for each device. Wall-clock time (`System.system_time(:millisecond)`) is
  used so that the debug view can render accurate absolute timings across
  page refreshes.

  The ring buffer for each device is kept newest-first and is trimmed to
  `@window_ms` on every write, but always keeps at least one entry that
  predates the window start so the bar can be drawn from the beginning of
  the 60-second window.

  Consumers call `get_all/0` or `get_history/1` to seed their local state.
  Subsequent updates arrive via the same per-sensor status PubSub topic
  that this module subscribes to (`Octopus.Radar.subscribe_status/1`).
  """

  use GenServer

  alias Octopus.Radar

  @window_ms 60_000

  ## Client API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc "Return the full history map: `%{device_id => [{wall_clock_ms, status}]}`, newest-first."
  @spec get_all() :: %{pos_integer() => [{integer(), atom()}]}
  def get_all do
    GenServer.call(__MODULE__, :get_all)
  end

  @doc "Return the history for one device: `[{wall_clock_ms, status}]`, newest-first."
  @spec get_history(pos_integer()) :: [{integer(), atom()}]
  def get_history(device_id) do
    GenServer.call(__MODULE__, {:get_history, device_id})
  end

  ## GenServer callbacks

  @impl true
  def init(_opts) do
    {:ok, %{}, {:continue, :subscribe}}
  end

  @impl true
  def handle_continue(:subscribe, _state) do
    if Radar.enabled?() do
      devices = Radar.devices()
      Enum.each(devices, &Radar.subscribe_status(&1.device_id))

      now = System.system_time(:millisecond)

      history =
        Map.new(devices, fn d ->
          status = Radar.sensor_status(d.device_id)
          {d.device_id, [{now, status}]}
        end)

      {:noreply, history}
    else
      {:noreply, %{}}
    end
  end

  @impl true
  def handle_call(:get_all, _from, history) do
    {:reply, history, history}
  end

  def handle_call({:get_history, device_id}, _from, history) do
    {:reply, Map.get(history, device_id, []), history}
  end

  @impl true
  def handle_info({:radar_sensor_status, device_id, status}, history) do
    now = System.system_time(:millisecond)
    entries = Map.get(history, device_id, [])
    entries = trim_entries([{now, status} | entries], now - @window_ms)
    {:noreply, Map.put(history, device_id, entries)}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  ## Private helpers

  defp trim_entries(entries, cutoff) do
    case Enum.split_while(entries, fn {t, _} -> t >= cutoff end) do
      {recent, []} -> recent
      {recent, [anchor | _]} -> recent ++ [anchor]
    end
  end
end
