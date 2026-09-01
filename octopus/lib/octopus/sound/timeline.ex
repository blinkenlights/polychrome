defmodule Octopus.Sound.Timeline do
  @moduledoc """
  Pure musical time.

  A timeline anchors a beat position to a monotonic timestamp. Position, the
  timestamp of a future step and tempo changes are all derived from that
  anchor, so the transport never accumulates drift: every answer is computed
  from the anchor rather than from the previous answer.

  Positions are counted in beats from the start of the transport. `bar`,
  `beat` and `step` in `position/2` are 1-based and wrapped into the loop, the
  way a sequencer displays them.
  """

  alias Octopus.Sound.Time

  @type t :: %__MODULE__{
          bpm: float(),
          beats_per_bar: pos_integer(),
          steps_per_beat: pos_integer(),
          loop_bars: pos_integer(),
          anchor_ms: integer(),
          anchor_beats: float(),
          playing?: boolean()
        }

  @type step :: %{index: integer(), beats: float()}

  defstruct bpm: 120.0,
            beats_per_bar: 4,
            steps_per_beat: 4,
            loop_bars: 8,
            anchor_ms: 0,
            anchor_beats: 0.0,
            playing?: false

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    struct!(__MODULE__, Keyword.put_new_lazy(opts, :anchor_ms, &Time.now/0))
  end

  @spec ms_per_beat(t()) :: float()
  def ms_per_beat(%__MODULE__{bpm: bpm}), do: 60_000 / bpm

  @spec beats_per_loop(t()) :: pos_integer()
  def beats_per_loop(%__MODULE__{beats_per_bar: per_bar, loop_bars: bars}), do: per_bar * bars

  @doc "Beat position at `now_ms`. A stopped timeline stays where it was."
  @spec beats_at(t(), integer()) :: float()
  def beats_at(%__MODULE__{playing?: false} = timeline, _now_ms), do: timeline.anchor_beats

  def beats_at(%__MODULE__{} = timeline, now_ms) do
    timeline.anchor_beats + (now_ms - timeline.anchor_ms) / ms_per_beat(timeline)
  end

  @doc """
  Monotonic timestamp at which `beats` is reached.

  Meaningful while playing; for a stopped timeline it extrapolates from the
  anchor, which is what a scheduler priming its window wants.
  """
  @spec ms_at(t(), number()) :: float()
  def ms_at(%__MODULE__{} = timeline, beats) do
    timeline.anchor_ms + (beats - timeline.anchor_beats) * ms_per_beat(timeline)
  end

  @spec play(t(), integer()) :: t()
  def play(%__MODULE__{playing?: true} = timeline, _now_ms), do: timeline

  def play(%__MODULE__{} = timeline, now_ms) do
    %{timeline | playing?: true, anchor_ms: now_ms}
  end

  @spec stop(t(), integer()) :: t()
  def stop(%__MODULE__{playing?: false} = timeline, _now_ms), do: timeline

  def stop(%__MODULE__{} = timeline, now_ms) do
    %{timeline | playing?: false, anchor_beats: beats_at(timeline, now_ms), anchor_ms: now_ms}
  end

  @doc "Changes tempo without moving the playhead."
  @spec set_bpm(t(), integer(), number()) :: t()
  def set_bpm(%__MODULE__{} = timeline, now_ms, bpm) when bpm > 0 do
    %{rebase(timeline, now_ms) | bpm: bpm / 1}
  end

  @spec seek(t(), integer(), number()) :: t()
  def seek(%__MODULE__{} = timeline, now_ms, beats) do
    %{timeline | anchor_ms: now_ms, anchor_beats: beats / 1}
  end

  @doc "Re-anchors to `now_ms` without changing the current position."
  @spec rebase(t(), integer()) :: t()
  def rebase(%__MODULE__{} = timeline, now_ms) do
    %{timeline | anchor_beats: beats_at(timeline, now_ms), anchor_ms: now_ms}
  end

  @doc """
  Display position: absolute beats plus 1-based bar/beat/step inside the loop.
  """
  @spec position(t(), integer()) :: map()
  def position(%__MODULE__{} = timeline, now_ms) do
    beats = beats_at(timeline, now_ms)
    in_loop = wrap(beats, beats_per_loop(timeline))
    whole = floor(in_loop)

    %{
      beats: beats,
      loop_beats: in_loop,
      bar: div(whole, timeline.beats_per_bar) + 1,
      beat: rem(whole, timeline.beats_per_bar) + 1,
      step: floor((in_loop - whole) * timeline.steps_per_beat) + 1,
      playing?: timeline.playing?,
      bpm: timeline.bpm
    }
  end

  @doc """
  Steps in the half-open beat range `(from_beats, to_beats]`.

  Half-open on purpose: consecutive calls that pass the previous `to` as the
  new `from` cover every step exactly once, with no gap and no repeat.
  """
  @spec steps_between(t(), number(), number()) :: [step()]
  def steps_between(%__MODULE__{steps_per_beat: per_beat}, from_beats, to_beats) do
    first = floor(from_beats * per_beat) + 1
    last = floor(to_beats * per_beat)

    if last < first do
      []
    else
      Enum.map(first..last, &%{index: &1, beats: &1 / per_beat})
    end
  end

  defp wrap(value, period) do
    rest = :math.fmod(value, period)
    if rest < 0, do: rest + period, else: rest
  end
end
