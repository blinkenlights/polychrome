defmodule Octopus.Sound.Engine.Null do
  @moduledoc """
  Engine that makes no sound. The default, so a machine without any audio
  setup still boots the sound stack and the transport can be worked on.
  """

  @behaviour Octopus.Sound.Engine

  require Logger

  @impl true
  def start_link(_opts), do: Agent.start_link(fn -> nil end, name: __MODULE__)

  def child_spec(opts) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}}
  end

  @impl true
  def capabilities do
    %{scheduling: :none, channels: Octopus.Sound.Engine.channels()}
  end

  @impl true
  def note(params) do
    Logger.debug("[sound] note #{inspect(params)}")
    :ok
  end

  @impl true
  def panic, do: :ok
end
