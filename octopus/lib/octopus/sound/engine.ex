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
  alias Phoenix.PubSub

  @topic "sound_notes"

  @type note :: %{
          channel: pos_integer(),
          note: number(),
          velocity: float(),
          duration_ms: number(),
          at_ms: integer(),
          synth: binary()
        }

  @typedoc "Identifies a sustained voice for the lifetime of its sound."
  @type voice :: term()

  @callback start_link(keyword()) :: GenServer.on_start()
  @callback capabilities() ::
              %{scheduling: :timestamped | :immediate | :none, channels: pos_integer()}
  @callback note(note()) :: :ok

  @doc """
  Starts a sustained voice under `id`, replacing one already sounding there.

  Sustained voices are what a picture can steer: the drone holds one per panel
  and moves its amplitude with the formula. Engines that cannot change a
  sounding note (beak) may ignore `set_voice/2` — the note still starts and
  stops, it just cannot breathe.
  """
  @callback voice(voice(), map()) :: :ok
  @callback set_voice(voice(), map()) :: :ok
  @callback release(voice()) :: :ok
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
  Receives `{:sound_note, note}` for every note played, whichever source it
  came from. Sparse enough to publish one message each — unlike frames.
  """
  def subscribe_notes, do: PubSub.subscribe(Octopus.PubSub, @topic)

  @doc """
  Plays one note. `:at_ms` is a monotonic timestamp (see `Octopus.Sound.Time`)
  and defaults to now.
  """
  @spec note(map()) :: :ok
  def note(params \\ %{}) do
    note =
      params
      |> Map.new()
      |> then(&Map.merge(@default_note, &1))
      |> Map.put_new_lazy(:at_ms, &Octopus.Sound.Time.now/0)

    result = module().note(note)

    if Process.whereis(Octopus.PubSub) do
      PubSub.broadcast(Octopus.PubSub, @topic, {:sound_note, note})
    end

    result
  end

  @spec capabilities() :: map()
  def capabilities, do: module().capabilities()

  @default_voice %{synth: "pc_voice", channel: 1, note: 48, amp: 0.0, cutoff: 2000.0}

  @doc "Starts (or restarts) a sustained voice."
  @spec voice(term(), map()) :: :ok
  def voice(id, params \\ %{}) do
    module().voice(id, Map.merge(@default_voice, Map.new(params)))
  end

  @doc "Changes a sounding voice — amplitude, cutoff, pitch."
  @spec set_voice(term(), map()) :: :ok
  def set_voice(id, params), do: module().set_voice(id, Map.new(params))

  @doc "Lets a sustained voice go; it fades out with its own release."
  @spec release(term()) :: :ok
  def release(id), do: module().release(id)

  @doc "Stops everything that is sounding, right now."
  @spec panic() :: :ok
  def panic, do: module().panic()

  @doc "Concert pitch frequency of a MIDI note number."
  @spec frequency(number()) :: float()
  def frequency(note), do: 440.0 * :math.pow(2, (note - 69) / 12)
end
