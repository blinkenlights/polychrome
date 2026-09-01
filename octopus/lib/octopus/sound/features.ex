defmodule Octopus.Sound.Features do
  @moduledoc """
  What the sound is doing right now, as numbers the picture can use.

  The classic sound-to-light direction, but measured on the inside: instead of
  a microphone listening to the room, this watches the notes the engine plays.
  That makes it exact and free of room latency — and it is the only reason the
  picture can react to a beat without hearing it first.

  Publishes `{:sound_features, %{level: 0..1, onset: 0..1}}` at a steady rate.
  """

  use GenServer

  alias Octopus.Sound.Engine
  alias Phoenix.PubSub

  @topic "sound_features"
  @interval_ms 50
  # An onset is a spike that has to be gone before the next note lands;
  # level is a loudness impression, which the ear holds much longer.
  @onset_decay 0.55
  @level_decay 0.9

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Receives `{:sound_features, features}`."
  def subscribe, do: PubSub.subscribe(Octopus.PubSub, @topic)

  def get, do: GenServer.call(__MODULE__, :get)

  @impl true
  def init(_opts) do
    Engine.subscribe_notes()
    {:ok, _} = :timer.send_interval(@interval_ms, :publish)
    {:ok, %{level: 0.0, onset: 0.0}}
  end

  @impl true
  def handle_call(:get, _from, state), do: {:reply, state, state}

  @impl true
  def handle_info({:sound_note, %{velocity: velocity}}, state) do
    {:noreply, %{state | level: max(state.level, velocity), onset: 1.0}}
  end

  def handle_info(:publish, state) do
    if Process.whereis(Octopus.PubSub) do
      PubSub.broadcast(Octopus.PubSub, @topic, {:sound_features, state})
    end

    {:noreply, %{state | level: state.level * @level_decay, onset: state.onset * @onset_decay}}
  end

  def handle_info(_message, state), do: {:noreply, state}
end
