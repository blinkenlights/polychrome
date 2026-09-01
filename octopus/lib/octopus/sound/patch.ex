defmodule Octopus.Sound.Patch do
  @moduledoc """
  Holds the pattern that is playing, and the one you are comparing it against.

  A single place of truth, so a reload of the browser, a second tab or a
  reconnect all see what is actually running — the studio only draws it.

  Two patterns are kept, A and B. Switching between them is one call, which is
  the whole point: "was the slower one better?" is a question you answer by
  ear, not from memory.
  """

  use GenServer

  alias Octopus.Sound.{Pattern, Scheduler}
  alias Phoenix.PubSub

  @topic "sound_patch"

  # -- API ------------------------------------------------------------------

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Receives `{:sound_patch, %{pattern: pattern, slot: :a | :b}}` on every change."
  def subscribe, do: PubSub.subscribe(Octopus.PubSub, @topic)

  @doc "The pattern currently playing."
  def pattern, do: GenServer.call(__MODULE__, :pattern)

  @doc "Which of the two is live."
  def slot, do: GenServer.call(__MODULE__, :slot)

  @doc "Replaces the live pattern."
  def put(%Pattern{} = pattern), do: GenServer.call(__MODULE__, {:put, pattern})

  @doc "Applies a function to the live pattern, e.g. `&Pattern.put_step(&1, 1, 0, 3)`."
  def update(fun) when is_function(fun, 1), do: GenServer.call(__MODULE__, {:update, fun})

  @doc "Switches between A and B."
  def switch, do: GenServer.call(__MODULE__, :switch)

  @doc "Copies the live pattern over the other slot, so a comparison starts from equals."
  def copy_to_other, do: GenServer.call(__MODULE__, :copy_to_other)

  # -- Server ---------------------------------------------------------------

  @impl true
  def init(opts) do
    pattern = Keyword.get(opts, :pattern) || Pattern.new()
    state = %{a: pattern, b: Pattern.new(), slot: :a}

    {:ok, state, {:continue, :install}}
  end

  @impl true
  def handle_continue(:install, state) do
    install(state)
    {:noreply, state}
  end

  @impl true
  def handle_call(:pattern, _from, state), do: {:reply, live(state), state}
  def handle_call(:slot, _from, state), do: {:reply, state.slot, state}

  def handle_call({:put, pattern}, _from, state) do
    {:reply, pattern, commit(%{state | state.slot => pattern})}
  end

  def handle_call({:update, fun}, _from, state) do
    pattern = fun.(live(state))
    {:reply, pattern, commit(%{state | state.slot => pattern})}
  end

  def handle_call(:switch, _from, state) do
    state = %{state | slot: other(state.slot)}
    {:reply, state.slot, commit(state)}
  end

  def handle_call(:copy_to_other, _from, state) do
    {:reply, :ok, commit(%{state | other(state.slot) => live(state)})}
  end

  # -- Internals ------------------------------------------------------------

  defp live(state), do: Map.fetch!(state, state.slot)

  defp other(:a), do: :b
  defp other(:b), do: :a

  defp commit(state) do
    install(state)
    state
  end

  # The scheduler holds a closure over the pattern, so every edit reinstalls it.
  # Cheap, and it means the scheduler never has to know what a pattern is.
  defp install(state) do
    pattern = live(state)

    if Process.whereis(Scheduler), do: Scheduler.set_source(Pattern.source(pattern))

    if Process.whereis(Octopus.PubSub) do
      PubSub.broadcast(
        Octopus.PubSub,
        @topic,
        {:sound_patch, %{pattern: pattern, slot: state.slot}}
      )
    end

    :ok
  end
end
