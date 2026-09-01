defmodule Octopus.Sound.Clock do
  @moduledoc """
  The transport: one musical clock for sound and picture.

  Holds a `Octopus.Sound.Timeline` and publishes its position on the
  `"sound_clock"` topic. Everything that should run in time — the scheduler
  today, beat-locked pixelfun sweeps later — reads its time here instead of
  counting on its own, which is what keeps the two sides from drifting apart.
  """

  use GenServer

  alias Octopus.Sound.{Time, Timeline}
  alias Phoenix.PubSub

  @topic "sound_clock"
  @broadcast_interval_ms 100

  # -- API ------------------------------------------------------------------

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def subscribe, do: PubSub.subscribe(Octopus.PubSub, @topic)

  @doc "Starts the transport at the position it was stopped at."
  def play, do: GenServer.call(__MODULE__, :play)
  def stop, do: GenServer.call(__MODULE__, :stop)
  def toggle, do: GenServer.call(__MODULE__, :toggle)

  @doc "Changes tempo without moving the playhead."
  def set_bpm(bpm) when is_number(bpm) and bpm > 0, do: GenServer.call(__MODULE__, {:bpm, bpm})

  @doc "Jumps to an absolute beat position."
  def seek(beats) when is_number(beats), do: GenServer.call(__MODULE__, {:seek, beats})

  def set_loop_bars(bars) when is_integer(bars) and bars > 0,
    do: GenServer.call(__MODULE__, {:loop_bars, bars})

  @doc "The timeline itself, for anyone doing their own musical math."
  def timeline, do: GenServer.call(__MODULE__, :timeline)

  @doc "Current position — beats plus 1-based bar/beat/step inside the loop."
  def position, do: Timeline.position(timeline(), Time.now())

  # -- Server ---------------------------------------------------------------

  @impl true
  def init(opts) do
    timeline =
      Timeline.new(
        bpm: Keyword.get(opts, :bpm, 120.0),
        beats_per_bar: Keyword.get(opts, :beats_per_bar, 4),
        steps_per_beat: Keyword.get(opts, :steps_per_beat, 4),
        loop_bars: Keyword.get(opts, :loop_bars, 8)
      )

    {:ok, _} = :timer.send_interval(@broadcast_interval_ms, :broadcast)
    {:ok, %{timeline: timeline}}
  end

  @impl true
  def handle_call(:play, _from, state), do: update(state, &Timeline.play(&1, Time.now()))
  def handle_call(:stop, _from, state), do: update(state, &Timeline.stop(&1, Time.now()))

  def handle_call(:toggle, _from, %{timeline: %{playing?: true}} = state),
    do: update(state, &Timeline.stop(&1, Time.now()))

  def handle_call(:toggle, _from, state), do: update(state, &Timeline.play(&1, Time.now()))

  def handle_call({:bpm, bpm}, _from, state),
    do: update(state, &Timeline.set_bpm(&1, Time.now(), bpm))

  def handle_call({:seek, beats}, _from, state),
    do: update(state, &Timeline.seek(&1, Time.now(), beats))

  def handle_call({:loop_bars, bars}, _from, state),
    do: update(state, &%{&1 | loop_bars: bars})

  def handle_call(:timeline, _from, state), do: {:reply, state.timeline, state}

  @impl true
  def handle_info(:broadcast, %{timeline: %{playing?: false}} = state), do: {:noreply, state}

  def handle_info(:broadcast, state) do
    broadcast(state.timeline)
    {:noreply, state}
  end

  defp update(state, fun) do
    timeline = fun.(state.timeline)
    broadcast(timeline)
    {:reply, Timeline.position(timeline, Time.now()), %{state | timeline: timeline}}
  end

  defp broadcast(timeline) do
    PubSub.broadcast(
      Octopus.PubSub,
      @topic,
      {:sound_clock, Timeline.position(timeline, Time.now())}
    )
  end
end
