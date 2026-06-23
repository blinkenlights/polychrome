defmodule Octopus.Apps.Collective.MockRadar do
  @moduledoc """
  Dev-only mock radar feed: drives an `Octopus.Apps.Collective.MockCrowd` and
  broadcasts it on the real radar PubSub topic as
  `{:radar_frame, device_id, %Octopus.Radar.Frame{}}`.

  This makes the mock crowd a first-class radar source: any existing consumer
  works unchanged — the 3D sim (`/sim3daframe`, set Humans → "Radar (live)"),
  the `Octopus.Apps.Collective` animations, `RadarLive`, etc. all see the same
  people. When Tim's real mock server (or hardware) lands, this process is simply
  not started and the consumers keep working against the identical envelope.

  Coordinates are already in the installation-global frame (meters, origin at the
  ring center), so — unlike a real sensor — no `Octopus.Radar.Transform` step is
  applied here; the mock produces global coordinates directly.

  Started from `Octopus.Application` only when enabled in config and no real
  sensor ports are present (see `application.ex`). Off by default outside dev.
  """

  use GenServer
  require Logger

  alias Octopus.Radar
  alias Octopus.Radar.{Frame, Track}
  alias Octopus.Apps.Collective.MockCrowd

  @device_id 1
  @tick_ms 50

  # --- Public API ----------------------------------------------------------

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Returns true if the mock radar process is currently running."
  @spec running?() :: boolean()
  def running?, do: Process.whereis(__MODULE__) != nil

  @doc "Sets the global movement speed multiplier (0.0 = everyone frozen)."
  @spec set_movement(float()) :: :ok
  def set_movement(movement) do
    if pid = Process.whereis(__MODULE__), do: GenServer.cast(pid, {:set_movement, movement})
    :ok
  end

  @doc "Spawns one person at 20 m (no-op if the mock is not running)."
  @spec spawn_person() :: :ok
  def spawn_person do
    if pid = Process.whereis(__MODULE__), do: GenServer.cast(pid, :spawn_person)
    :ok
  end

  # --- GenServer -----------------------------------------------------------

  @impl true
  def init(opts) do
    movement = Keyword.get(opts, :movement, 1.0)

    Logger.info("[radar_mock] Mock radar feed started (autonomous 1-20 people on #{Radar.topic()})")

    :timer.send_interval(@tick_ms, :tick)

    {:ok,
     %{
       crowd: MockCrowd.new(),
       movement: movement,
       frame_number: 0,
       last_update: now_ms()
     }}
  end

  @impl true
  def handle_cast({:set_movement, movement}, state) do
    {:noreply, %{state | movement: max(movement, 0.0)}}
  end

  def handle_cast(:spawn_person, state) do
    {:noreply, %{state | crowd: MockCrowd.spawn_person(state.crowd)}}
  end

  @impl true
  def handle_info(:tick, state) do
    now = now_ms()
    dt = max(now - state.last_update, 0) / 1000.0

    crowd = MockCrowd.update(state.crowd, dt, state.movement)
    frame_number = state.frame_number + 1
    frame = build_frame(MockCrowd.people(crowd), frame_number)

    broadcast(frame)

    {:noreply, %{state | crowd: crowd, frame_number: frame_number, last_update: now}}
  end

  # --- helpers -------------------------------------------------------------

  defp build_frame(people, frame_number) do
    tracks =
      Enum.map(people, fn p ->
        %Track{
          id: p.id,
          reserved: 0,
          x: p.x,
          y: p.y,
          z: 0.0,
          vx: p.vx,
          vy: p.vy,
          vz: 0.0
        }
      end)

    %Frame{
      frame_number: frame_number,
      tracks: tracks,
      received_at: System.monotonic_time(:millisecond)
    }
  end

  defp broadcast(%Frame{} = frame) do
    envelope = {:radar_frame, @device_id, frame}
    Phoenix.PubSub.broadcast(Octopus.PubSub, Radar.topic(), envelope)
    Phoenix.PubSub.broadcast(Octopus.PubSub, Radar.topic(@device_id), envelope)
  end

  defp now_ms, do: :erlang.monotonic_time(:millisecond)
end
