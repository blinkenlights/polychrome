defmodule Octopus.Sound.Pattern do
  @moduledoc """
  A loop of steps, and where on the ring each of them sounds.

  Rows are slots, columns are the steps of the loop — the grid every drum
  machine has. What is different here is that a set step carries a **panel**:
  not only when it sounds, but where. On a ring of speakers that turns the
  grid into a way of composing movement, which is the whole reason this
  installation has one channel per panel.

  A slot is three things, and everything the studio can make sounds with fits
  under them: a **sound** (synth and its parameters), a **trigger** — the grid,
  a probe crossing zero, or simply held — and a **place**, the rule that decides
  which channel it sounds on. The ring chase and the drone are not separate
  instruments in this model; they are slots whose trigger and place differ.

  Pure data: the scheduler asks `notes_for/2` with an absolute step counter and
  gets back notes for the grid-triggered slots. The other two kinds are read by
  whoever owns their trigger.
  """

  alias Octopus.Sound.Engine

  @typedoc """
  What makes a slot sound.

  `:grid` follows the steps, `:probe` fires when the formula rises through zero
  at a panel, `:held` sounds continuously with its loudness modulated. Probe
  triggers carry their own gate settings — the steepness a crossing needs is a
  property of the trigger, not of the sound.
  """
  @type trigger ::
          %{kind: :grid}
          | %{kind: :probe, min_rise: float(), min_interval_ms: non_neg_integer()}
          | %{kind: :held}

  @typedoc """
  Where a slot sounds.

  `:step` takes the channel from the step in the grid — one place per beat, which
  is what makes this grid different from a groovebox. The others are rules that
  hold for the whole slot.
  """
  @type channel ::
          %{mode: :step}
          | %{mode: :fixed, panel: pos_integer()}
          | %{mode: :follow_probe}
          | %{mode: :all_panels}
          | %{mode: :rotate, step: pos_integer()}

  @type slot :: %{
          id: pos_integer(),
          name: String.t(),
          synth: String.t(),
          note: integer(),
          duration_ms: pos_integer(),
          muted?: boolean(),
          trigger: trigger(),
          channel: channel(),
          steps: %{non_neg_integer() => %{panel: pos_integer(), velocity: float()}}
        }

  @type t :: %__MODULE__{slots: [slot()], steps: pos_integer()}

  defstruct slots: [], steps: 16

  @default_slots 8
  @default_steps 16
  @default_velocity 0.7
  # D dorian again, so slots stacked on top of each other still agree.
  @scale [62, 65, 69, 72, 64, 67, 71, 74]
  @synths ["pc_ping", "pc_pluck", "pc_click", "pc_drone", "pc_voice"]

  @default_trigger %{kind: :grid}
  @default_channel %{mode: :step}
  # Same numbers the ring chase used when it was an instrument of its own, so a
  # slot set up as a chase behaves exactly as before.
  @default_probe_trigger %{kind: :probe, min_rise: 0.002, min_interval_ms: 60}

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    count = Keyword.get(opts, :slots, @default_slots)
    steps = Keyword.get(opts, :steps, @default_steps)

    %__MODULE__{
      steps: steps,
      slots:
        for id <- 1..count do
          %{
            id: id,
            name: "Slot #{id}",
            synth: Enum.at(@synths, rem(id - 1, length(@synths))),
            note: Enum.at(@scale, rem(id - 1, length(@scale))),
            duration_ms: 300,
            muted?: false,
            trigger: @default_trigger,
            channel: @default_channel,
            steps: %{}
          }
        end
    }
  end

  def synths, do: @synths

  def default_trigger, do: @default_trigger
  def default_channel, do: @default_channel
  def probe_trigger, do: @default_probe_trigger

  @doc "Slots the grid plays — the only ones `notes_for/2` answers with."
  @spec grid_slots(t()) :: [slot()]
  def grid_slots(%__MODULE__{slots: slots}), do: Enum.filter(slots, &(&1.trigger.kind == :grid))

  @doc "Slots a probe crossing zero sets off."
  @spec probe_slots(t()) :: [slot()]
  def probe_slots(%__MODULE__{slots: slots}),
    do: Enum.filter(slots, &(&1.trigger.kind == :probe and not &1.muted?))

  @doc "Slots that sound continuously, their loudness following the picture."
  @spec held_slots(t()) :: [slot()]
  def held_slots(%__MODULE__{slots: slots}),
    do: Enum.filter(slots, &(&1.trigger.kind == :held and not &1.muted?))

  @doc """
  Channels a slot sounds on for one trigger.

  `panel` is where the trigger happened — the step's panel for the grid, the
  probe's panel for a crossing. `count` is how often this slot has fired, which
  only `:rotate` cares about.
  """
  @spec channels_for(slot(), pos_integer(), non_neg_integer(), pos_integer()) :: [pos_integer()]
  def channels_for(slot, panel, count \\ 0, panels \\ 12)

  def channels_for(%{channel: %{mode: :step}}, panel, _count, _panels), do: [panel]
  def channels_for(%{channel: %{mode: :follow_probe}}, panel, _count, _panels), do: [panel]

  def channels_for(%{channel: %{mode: :fixed, panel: fixed}}, _panel, _count, _panels),
    do: [fixed]

  def channels_for(%{channel: %{mode: :all_panels}}, _panel, _count, panels),
    do: Enum.to_list(1..panels)

  def channels_for(%{channel: %{mode: :rotate, step: step}}, panel, count, panels) do
    [Integer.mod(panel - 1 + count * step, panels) + 1]
  end

  def channels_for(_slot, panel, _count, _panels), do: [panel]

  @doc """
  Sets a step to `panel`, or clears it when it already holds that panel.

  One click does both, the way a step button on a groovebox does — and moving
  a step to another panel is the same gesture with a different brush.
  """
  @spec put_step(t(), pos_integer(), non_neg_integer(), pos_integer()) :: t()
  def put_step(%__MODULE__{} = pattern, slot_id, step, panel) do
    update_slot(pattern, slot_id, fn slot ->
      case Map.get(slot.steps, step) do
        %{panel: ^panel} -> %{slot | steps: Map.delete(slot.steps, step)}
        _ -> %{slot | steps: Map.put(slot.steps, step, cell(panel))}
      end
    end)
  end

  @spec clear_step(t(), pos_integer(), non_neg_integer()) :: t()
  def clear_step(%__MODULE__{} = pattern, slot_id, step) do
    update_slot(pattern, slot_id, &%{&1 | steps: Map.delete(&1.steps, step)})
  end

  @spec clear_slot(t(), pos_integer()) :: t()
  def clear_slot(%__MODULE__{} = pattern, slot_id) do
    update_slot(pattern, slot_id, &%{&1 | steps: %{}})
  end

  @spec toggle_mute(t(), pos_integer()) :: t()
  def toggle_mute(%__MODULE__{} = pattern, slot_id) do
    update_slot(pattern, slot_id, &%{&1 | muted?: not &1.muted?})
  end

  @spec configure_slot(t(), pos_integer(), map()) :: t()
  def configure_slot(%__MODULE__{} = pattern, slot_id, attrs) do
    update_slot(pattern, slot_id, fn slot ->
      Enum.reduce(attrs, slot, fn {key, value}, slot -> Map.replace(slot, key, value) end)
    end)
  end

  @doc "Wraps an absolute step counter into the loop."
  @spec index_of(t(), integer()) :: non_neg_integer()
  def index_of(%__MODULE__{steps: steps}, absolute_step) do
    Integer.mod(absolute_step, steps)
  end

  @doc """
  Notes for one absolute step of the transport.

  Only grid-triggered slots answer here; muted ones stay silent. A slot may
  produce several notes when its place rule spreads it across the ring.
  """
  @spec notes_for(t(), integer(), pos_integer()) :: [map()]
  def notes_for(%__MODULE__{} = pattern, absolute_step, panels \\ 12) do
    index = index_of(pattern, absolute_step)

    for slot <- grid_slots(pattern),
        not slot.muted?,
        cell = Map.get(slot.steps, index),
        cell != nil,
        channel <- channels_for(slot, cell.panel, absolute_step, panels) do
      %{
        channel: channel,
        note: slot.note,
        velocity: cell.velocity,
        duration_ms: slot.duration_ms,
        synth: slot.synth
      }
    end
  end

  @doc "Event source for `Octopus.Sound.Scheduler`."
  @spec source(t()) :: (map(), any() -> [map()])
  def source(%__MODULE__{} = pattern) do
    panels = Engine.panels()
    fn step, _timeline -> notes_for(pattern, step.index, panels) end
  end

  @doc "True when no slot has a single step set — an empty grid makes no sound."
  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{slots: slots}), do: Enum.all?(slots, &(&1.steps == %{}))

  @doc "Highest panel used anywhere, for sanity checks against an installation."
  @spec max_panel(t()) :: non_neg_integer()
  def max_panel(%__MODULE__{slots: slots}) do
    slots
    |> Enum.flat_map(fn slot -> Enum.map(slot.steps, fn {_index, cell} -> cell.panel end) end)
    |> Enum.max(fn -> 0 end)
  end

  # -- Serialisation --------------------------------------------------------

  @doc "Plain map with string keys, ready for the database."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = pattern) do
    %{
      "steps" => pattern.steps,
      "slots" =>
        Enum.map(pattern.slots, fn slot ->
          %{
            "id" => slot.id,
            "name" => slot.name,
            "synth" => slot.synth,
            "note" => slot.note,
            "duration_ms" => slot.duration_ms,
            "muted" => slot.muted?,
            "trigger" => stringify(slot.trigger),
            "channel" => stringify(slot.channel),
            "steps" =>
              Map.new(slot.steps, fn {index, cell} ->
                {to_string(index), %{"panel" => cell.panel, "velocity" => cell.velocity}}
              end)
          }
        end)
    }
  end

  @doc "Inverse of `to_map/1`. Unknown or broken input falls back to an empty grid."
  @spec from_map(any()) :: t()
  def from_map(%{"slots" => slots, "steps" => steps}) when is_list(slots) do
    %__MODULE__{
      steps: steps,
      slots: Enum.map(slots, &slot_from_map/1)
    }
  end

  def from_map(_other), do: new()

  defp slot_from_map(slot) do
    %{
      id: slot["id"],
      name: slot["name"],
      synth: slot["synth"],
      note: slot["note"],
      duration_ms: slot["duration_ms"],
      muted?: slot["muted"] == true,
      trigger: trigger_from_map(slot["trigger"]),
      channel: channel_from_map(slot["channel"]),
      steps:
        Map.new(slot["steps"] || %{}, fn {index, cell} ->
          {String.to_integer(to_string(index)),
           %{panel: cell["panel"], velocity: cell["velocity"] || @default_velocity}}
        end)
    }
  end

  # Atoms only ever come from these lists, never from stored text.
  @trigger_kinds %{"grid" => :grid, "probe" => :probe, "held" => :held}
  @channel_modes %{
    "step" => :step,
    "fixed" => :fixed,
    "follow_probe" => :follow_probe,
    "all_panels" => :all_panels,
    "rotate" => :rotate
  }

  defp stringify(map) do
    Map.new(map, fn {key, value} ->
      {to_string(key), if(is_atom(value), do: to_string(value), else: value)}
    end)
  end

  # Compositions saved before slots had a trigger read as plain grid slots,
  # which is what they were.
  defp trigger_from_map(%{"kind" => kind} = trigger) when is_map_key(@trigger_kinds, kind) do
    case Map.fetch!(@trigger_kinds, kind) do
      :probe ->
        %{
          kind: :probe,
          min_rise: trigger["min_rise"] || @default_probe_trigger.min_rise,
          min_interval_ms: trigger["min_interval_ms"] || @default_probe_trigger.min_interval_ms
        }

      kind ->
        %{kind: kind}
    end
  end

  defp trigger_from_map(_other), do: @default_trigger

  defp channel_from_map(%{"mode" => mode} = channel) when is_map_key(@channel_modes, mode) do
    case Map.fetch!(@channel_modes, mode) do
      :fixed -> %{mode: :fixed, panel: channel["panel"] || 1}
      :rotate -> %{mode: :rotate, step: channel["step"] || 1}
      mode -> %{mode: mode}
    end
  end

  defp channel_from_map(_other), do: @default_channel

  # -- Internals ------------------------------------------------------------

  defp cell(panel), do: %{panel: panel, velocity: @default_velocity}

  defp update_slot(%__MODULE__{} = pattern, slot_id, fun) do
    slots =
      Enum.map(pattern.slots, fn
        %{id: ^slot_id} = slot -> fun.(slot)
        slot -> slot
      end)

    %{pattern | slots: slots}
  end

  @doc false
  def default_channel_count, do: Engine.channels()
end
