defmodule Octopus.Sound.Drone do
  @moduledoc """
  One held voice per panel, its loudness following the picture.

  Every panel gets a pitch from a scale and a sustained voice. The formula
  value at that panel is its amplitude — where the pattern is bright, that
  pitch is audible; where it is dark, it disappears. The chord changes because
  the picture changes, and zooming out until the pattern is fine turns a
  three-note drone into a shimmer.

  Only the positive half of the formula sounds. Using the absolute value would
  make every panel audible on both halves of the wave, which flattens exactly
  the movement this is meant to expose.
  """

  use GenServer

  alias Octopus.Sound.{Engine, Probes}

  # Slow enough that a bright panel has to stay bright to be heard.
  @default_gain 0.7
  # D dorian across the ring, low to high, so neighbours are consonant.
  @default_scale [38, 45, 50, 53, 57, 60, 62, 65, 69, 72, 74, 77]
  @default_cutoff 1800

  # -- API ------------------------------------------------------------------

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Starts or stops the drone. Stopping releases every voice."
  def enable(on?) when is_boolean(on?), do: GenServer.call(__MODULE__, {:enable, on?})

  def enabled?, do: GenServer.call(__MODULE__, :enabled?)

  @doc "Adjusts `:gain`, `:cutoff`, `:scale`."
  def configure(opts) when is_list(opts), do: GenServer.call(__MODULE__, {:configure, opts})

  def state, do: GenServer.call(__MODULE__, :state)

  @doc "Amplitude for a probe reading: the positive half, scaled."
  @spec amplitude(float(), float()) :: float()
  def amplitude(value, gain), do: max(value, 0.0) * gain

  # -- Server ---------------------------------------------------------------

  @impl true
  def init(opts) do
    {:ok,
     %{
       enabled?: Keyword.get(opts, :enabled, false),
       gain: Keyword.get(opts, :gain, @default_gain),
       cutoff: Keyword.get(opts, :cutoff, @default_cutoff),
       scale: Keyword.get(opts, :scale, @default_scale),
       voices: []
     }}
  end

  @impl true
  def handle_call({:enable, true}, _from, %{enabled?: false} = state) do
    Probes.subscribe()
    {:reply, :ok, start_voices(state)}
  end

  def handle_call({:enable, false}, _from, %{enabled?: true} = state) do
    Probes.unsubscribe()
    {:reply, :ok, stop_voices(state)}
  end

  def handle_call({:enable, _on?}, _from, state), do: {:reply, :ok, state}
  def handle_call(:enabled?, _from, state), do: {:reply, state.enabled?, state}
  def handle_call(:state, _from, state), do: {:reply, Map.drop(state, [:voices]), state}

  def handle_call({:configure, opts}, _from, state) do
    state = Enum.reduce(opts, state, fn {key, value}, state -> Map.replace(state, key, value) end)

    for id <- state.voices, do: Engine.set_voice(id, %{cutoff: state.cutoff})
    {:reply, :ok, state}
  end

  @impl true
  def handle_info({:pixel_probes, %{values: values}}, %{enabled?: true} = state) do
    values
    |> Enum.with_index()
    |> Enum.each(fn {value, index} ->
      Engine.set_voice(voice_id(index), %{amp: amplitude(value, state.gain)})
    end)

    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state), do: stop_voices(state)

  # -- Internals ------------------------------------------------------------

  defp start_voices(state) do
    voices =
      for index <- 0..(Engine.channels() - 1) do
        id = voice_id(index)

        Engine.voice(id, %{
          channel: index + 1,
          note: Enum.at(state.scale, rem(index, length(state.scale))),
          amp: 0.0,
          cutoff: state.cutoff
        })

        id
      end

    %{state | enabled?: true, voices: voices}
  end

  defp stop_voices(state) do
    for id <- state.voices, do: Engine.release(id)
    %{state | enabled?: false, voices: []}
  end

  defp voice_id(index), do: {:drone, index}
end
