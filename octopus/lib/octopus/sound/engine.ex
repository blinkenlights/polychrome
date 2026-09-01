defmodule Octopus.Sound.Engine do
  @moduledoc """
  What the sound stack expects from a sound engine.

  Two backends exist for the same contract: `beak` is what the installation
  runs today, SuperCollider is where this is going. The composition layer
  above never learns which one is active — apart from `capabilities/0`, where
  the difference matters: `:timestamped` engines execute an event at the
  timestamp they were given, `:immediate` engines play when the message
  arrives, so the scheduler has to hold events back itself.

  Channels are 1-based and mean panels: channel 3 is the speaker at panel 3.
  """

  alias Octopus.Installation

  @type note :: %{
          channel: pos_integer(),
          note: number(),
          velocity: float(),
          duration_ms: number(),
          at_ms: integer(),
          synth: binary()
        }

  @callback start_link(keyword()) :: GenServer.on_start()
  @callback capabilities() :: %{scheduling: :timestamped | :immediate, channels: pos_integer()}
  @callback note(note()) :: :ok
  @callback panic() :: :ok

  @default_note %{
    channel: 1,
    note: 69,
    velocity: 0.8,
    duration_ms: 200,
    synth: "pc_ping"
  }

  @doc "The configured backend module."
  @spec module() :: module()
  def module do
    config() |> Keyword.get(:engine, Octopus.Sound.Engine.Null)
  end

  @spec config() :: keyword()
  def config, do: Application.get_env(:octopus, Octopus.Sound, [])

  @doc "Number of output channels — one per panel unless configured otherwise."
  @spec channels() :: pos_integer()
  def channels do
    case Keyword.get(config(), :channels) do
      nil -> Installation.num_panels()
      channels when is_integer(channels) and channels > 0 -> channels
    end
  end

  @doc """
  Plays one note. `:at_ms` is a monotonic timestamp (see `Octopus.Sound.Time`)
  and defaults to now.
  """
  @spec note(map()) :: :ok
  def note(params \\ %{}) do
    params
    |> Map.new()
    |> then(&Map.merge(@default_note, &1))
    |> Map.put_new_lazy(:at_ms, &Octopus.Sound.Time.now/0)
    |> module().note()
  end

  @spec capabilities() :: map()
  def capabilities, do: module().capabilities()

  @doc "Stops everything that is sounding, right now."
  @spec panic() :: :ok
  def panic, do: module().panic()

  @doc "Concert pitch frequency of a MIDI note number."
  @spec frequency(number()) :: float()
  def frequency(note), do: 440.0 * :math.pow(2, (note - 69) / 12)
end
