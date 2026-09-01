defmodule Octopus.Sound.Pattern do
  @moduledoc """
  A loop of steps, and where on the ring each of them sounds.

  Rows are slots, columns are the steps of the loop — the grid every drum
  machine has. What is different here is that a set step carries a **panel**:
  not only when it sounds, but where. On a ring of speakers that turns the
  grid into a way of composing movement, which is the whole reason this
  installation has one channel per panel.

  Pure data: the scheduler asks `notes_for/2` with an absolute step counter and
  gets back notes. Nothing in here knows about time.
  """

  alias Octopus.Sound.Engine

  @type slot :: %{
          id: pos_integer(),
          name: String.t(),
          synth: String.t(),
          note: integer(),
          duration_ms: pos_integer(),
          muted?: boolean(),
          steps: %{non_neg_integer() => %{panel: pos_integer(), velocity: float()}}
        }

  @type t :: %__MODULE__{slots: [slot()], steps: pos_integer()}

  defstruct slots: [], steps: 16

  @default_slots 8
  @default_steps 16
  @default_velocity 0.7
  # D dorian again, so slots stacked on top of each other still agree.
  @scale [62, 65, 69, 72, 64, 67, 71, 74]
  @synths ["pc_ping", "pc_pluck", "pc_click", "pc_drone"]

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
            steps: %{}
          }
        end
    }
  end

  def synths, do: @synths

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

  @doc "Notes for one absolute step of the transport, muted slots left out."
  @spec notes_for(t(), integer()) :: [map()]
  def notes_for(%__MODULE__{} = pattern, absolute_step) do
    index = index_of(pattern, absolute_step)

    for slot <- pattern.slots,
        not slot.muted?,
        cell = Map.get(slot.steps, index),
        cell != nil do
      %{
        channel: cell.panel,
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
    fn step, _timeline -> notes_for(pattern, step.index) end
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
      steps:
        Map.new(slot["steps"] || %{}, fn {index, cell} ->
          {String.to_integer(to_string(index)),
           %{panel: cell["panel"], velocity: cell["velocity"] || @default_velocity}}
        end)
    }
  end

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
