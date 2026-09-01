defmodule Octopus.Sound.Engine.Recorder do
  @moduledoc """
  Test engine: forwards every note to the attached process instead of making
  sound. Reports `:timestamped` so the scheduler hands notes over as soon as
  it plans them, which is what a test wants to observe.
  """

  @behaviour Octopus.Sound.Engine

  @key {__MODULE__, :owner}

  @impl true
  def start_link(_opts), do: Agent.start_link(fn -> nil end, name: __MODULE__)

  def child_spec(opts), do: %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}}

  @doc "Sends every following note to `pid` as `{:note, params}`."
  def attach(pid \\ self()), do: :persistent_term.put(@key, pid)

  def detach, do: :persistent_term.erase(@key)

  @impl true
  def capabilities, do: %{scheduling: :timestamped, channels: 12}

  @impl true
  def note(params), do: tell({:note, params})

  defp tell(message) do
    case :persistent_term.get(@key, nil) do
      nil -> :ok
      pid -> send(pid, message)
    end

    :ok
  end

  @impl true
  def voice(id, params), do: tell({:voice, id, params})

  @impl true
  def set_voice(id, params), do: tell({:set_voice, id, params})

  @impl true
  def release(id), do: tell({:release, id})

  @impl true
  def panic do
    case :persistent_term.get(@key, nil) do
      nil -> :ok
      pid -> send(pid, :panic)
    end

    :ok
  end
end
