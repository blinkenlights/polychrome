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

  `:grid` follows the steps, `:held` sounds continuously with its loudness
  modulated, and `:probe` fires when a measured quantity at a panel rises
  through a level.

  Which quantity matters more than it looks. Pixel Fun paints a panel with
  brightness `|value|` — black at zero, brightest at ±1 — so a trigger on the
  **value** crossing zero fires exactly when the panel is *dark*, a quarter
  wave away from the bright band the eye is following. That reads as random
  however precise the timing is. `:brightness` crossing a level fires as the
  band arrives, which is the moment a person sees. `:speed` watches how fast
  the panel is changing rather than how bright it is — it fires on the steep
  flank between dark and bright, and stays quiet while a panel sits still,
  however bright it sits.

  The gate settings belong here too: how steep a crossing must be, and how
  soon a panel may fire again, are properties of the trigger and not of the
  sound.
  """
  @type trigger ::
          %{kind: :grid}
          | %{
              kind: :probe,
              quantity: :brightness | :value | :speed,
              level: float(),
              min_rise: float(),
              min_interval_ms: non_neg_integer()
            }
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
          gain: float(),
          scale: [integer()],
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
  # A one-shot sound ends by itself; a held one has a gate and only stops when
  # it is let go. Offering a held sound to a slot that fires it as a note is how
  # you get a tone nothing can switch off but panic.
  @one_shot_synths ["pc_ping", "pc_pluck", "pc_click", "pc_drone"]
  @held_synths ["pc_voice", "pc_drone"]
  @synths @one_shot_synths ++ ["pc_voice"]

  # A slot sounds one pitch — its root — unless its place spreads it around the
  # ring. Then the scale says what the panels sound: offsets from the root,
  # wrapping into the next octave when the ring is longer than the scale. That
  # is what makes a drone a chord and a chase a rising line, and it is the same
  # mechanism for both.
  @default_scale [0]
  @dorian [0, 2, 3, 5, 7, 9, 10]
  # A wide voicing, low to high — one drone voice per panel of a twelve panel
  # ring without two panels landing on the same pitch.
  @drone_voicing [0, 7, 12, 15, 19, 22, 24, 27, 31, 34, 36, 39]

  @default_trigger %{kind: :grid}
  @default_channel %{mode: :step}
  # Same numbers the ring chase used when it was an instrument of its own, so a
  # slot set up as a chase behaves exactly as before.
  # Brightness at a bit over half: high enough that only a real band sets it
  # off, low enough that it fires as the band arrives rather than at its peak,
  # where a note would already feel late.
  @default_probe_trigger %{
    kind: :probe,
    quantity: :brightness,
    level: 0.55,
    min_rise: 0.002,
    min_interval_ms: 60
  }

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
            gain: 0.7,
            scale: @default_scale,
            trigger: @default_trigger,
            channel: @default_channel,
            steps: %{}
          }
        end
    }
  end

  def synths, do: @synths

  @doc """
  The place rules a slot can be given, with what each means.

  Kept here rather than in the page so the studio and anything else naming
  them agree on the list.
  """
  @spec channel_modes() :: [{atom(), String.t()}]
  def channel_modes do
    [
      {:step, "aus dem Schritt"},
      {:fixed, "festes Panel"},
      {:follow_probe, "folgt Probe"},
      {:all_panels, "alle Panels"},
      {:rotate, "rotiert"}
    ]
  end

  @doc "Sounds that make sense for a trigger — see `@one_shot_synths`."
  @spec synths_for(atom()) :: [String.t()]
  def synths_for(:held), do: @held_synths
  def synths_for(_kind), do: @one_shot_synths

  @doc """
  A slot's sound, corrected if its trigger cannot use it.

  Changing a slot from held to triggered would otherwise leave a gated sound
  behind that nothing closes.
  """
  @spec valid_synth(map()) :: String.t()
  def valid_synth(%{synth: synth, trigger: %{kind: kind}}) do
    allowed = synths_for(kind)
    if synth in allowed, do: synth, else: hd(allowed)
  end

  @doc """
  Named pitch sets a slot can be given.

  A "scale" here is simply an ordered list of semitone offsets from the root,
  which is general enough to hold a mode, a pentatonic, or a wide voicing that
  is no scale at all. Naming them is convenience; the mechanism underneath is
  the list.
  """
  @spec scales() :: [{String.t(), [integer()]}]
  def scales do
    [
      {"Einzelton", [0]},
      {"Ionisch (Dur)", [0, 2, 4, 5, 7, 9, 11]},
      {"Dorisch", @dorian},
      {"Phrygisch", [0, 1, 3, 5, 7, 8, 10]},
      {"Lydisch", [0, 2, 4, 6, 7, 9, 11]},
      {"Mixolydisch", [0, 2, 4, 5, 7, 9, 10]},
      {"Äolisch (Moll)", [0, 2, 3, 5, 7, 8, 10]},
      {"Lokrisch", [0, 1, 3, 5, 6, 8, 10]},
      {"Dur-Pentatonik", [0, 2, 4, 7, 9]},
      {"Moll-Pentatonik", [0, 3, 5, 7, 10]},
      {"Blues", [0, 3, 5, 6, 7, 10]},
      {"Harmonisch Moll", [0, 2, 3, 5, 7, 8, 11]},
      {"Ganzton", [0, 2, 4, 6, 8, 10]},
      {"Chromatisch", Enum.to_list(0..11)},
      {"Quarten (weit)", [0, 5, 10, 15, 20, 25]},
      {"Drone-Lage (weit)", @drone_voicing}
    ]
  end

  @doc ~S(The name of a pitch set, or "eigene" when it matches none of them.)
  @spec scale_name([integer()]) :: String.t()
  def scale_name(scale) do
    Enum.find_value(scales(), "eigene", fn {name, offsets} ->
      if offsets == scale, do: name
    end)
  end

  @note_names ~w(C C♯ D D♯ E F F♯ G G♯ A A♯ H)

  @doc "MIDI note as a name with its octave, for the studio."
  @spec note_name(integer()) :: String.t()
  def note_name(note) do
    "#{Enum.at(@note_names, Integer.mod(note, 12))}#{div(note, 12) - 1}"
  end

  def dorian, do: @dorian
  def drone_voicing, do: @drone_voicing

  @doc """
  Pitch a slot sounds on a given panel.

  With the default single-step scale every panel gets the root, which is what a
  slot placed by hand wants. A scale with more steps turns the ring into a
  voicing, rising by an octave whenever it runs out — so no two panels of a
  twelve panel ring share a pitch.
  """
  @spec pitch_for(slot(), pos_integer()) :: integer()
  def pitch_for(%{note: root, scale: [_single]}, _panel), do: root

  def pitch_for(%{note: root, scale: scale}, panel) when is_list(scale) and scale != [] do
    index = panel - 1
    size = length(scale)

    # Rising by an octave past the end of the scale keeps two panels of a ring
    # from landing on the same pitch. A scale of one step is the monophonic
    # case — there the whole point is that every panel sounds the same.
    root + Enum.at(scale, Integer.mod(index, size)) + 12 * div(index, size)
  end

  def pitch_for(%{note: root}, _panel), do: root

  def default_trigger, do: @default_trigger
  def default_channel, do: @default_channel
  def probe_trigger, do: @default_probe_trigger

  @doc "What a probe trigger can watch, and what a person sees of it."
  @spec probe_quantities() :: [{atom(), String.t()}]
  def probe_quantities do
    [
      {:brightness, "Helligkeit — feuert, wenn das Panel aufleuchtet"},
      {:speed, "Tempo — feuert, wenn sich das Panel schnell ändert"},
      {:value, "Formelwert — feuert am Nulldurchgang, also im Dunkeln"}
    ]
  end

  @doc """
  A level and a steepness gate that mean something for this quantity.

  The three quantities live on different scales — brightness and value are the
  reading itself in −1…1, speed is how far the reading moves per second, which
  runs well past 1 — so carrying the old numbers across a change of quantity
  would silence the slot or open it wide. Switching quantity starts from these.
  """
  @spec gate_for(atom()) :: %{level: float(), min_rise: float()}
  def gate_for(:speed), do: %{level: 1.0, min_rise: 0.2}
  def gate_for(:brightness), do: %{level: 0.55, min_rise: 0.002}
  def gate_for(_value), do: %{level: 0.0, min_rise: 0.002}

  @doc """
  The quantity a probe trigger watches, from a single raw reading.

  Brightness is what the wall shows: the picture paints `|value|`, so both
  halves of a wave are a visible band. `:speed` is deliberately absent — it
  cannot be read off one frame, and `Octopus.Sound.Trigger.Probe.series/4`
  measures it from three.
  """
  @spec measure(atom(), float()) :: float()
  def measure(:brightness, value), do: abs(value)
  def measure(_quantity, value), do: value

  @doc """
  Turns a slot into a ring chase: set off by the picture, sounding where the
  wave is, rising through the scale around the ring.

  This is the one-click path from `docs/pixelfun-av/10-slot-modell.md` — it
  fills a slot rather than starting something beside it, so what you hear is
  always in the list and always saved.
  """
  @spec as_chase(t(), pos_integer(), keyword()) :: t()
  def as_chase(%__MODULE__{} = pattern, slot_id, opts \\ []) do
    configure_slot(pattern, slot_id, %{
      name: Keyword.get(opts, :name, "Chase"),
      synth: Keyword.get(opts, :synth, "pc_ping"),
      note: Keyword.get(opts, :note, 62),
      duration_ms: Keyword.get(opts, :duration_ms, 400),
      gain: Keyword.get(opts, :gain, 0.7),
      scale: Keyword.get(opts, :scale, @dorian),
      trigger: Map.merge(@default_probe_trigger, Map.new(Keyword.get(opts, :trigger, []))),
      channel: %{mode: :follow_probe}
    })
  end

  @doc """
  Turns a slot into a drone: one held voice per panel, its loudness following
  the formula there, the panels together forming a chord.
  """
  @spec as_drone(t(), pos_integer(), keyword()) :: t()
  def as_drone(%__MODULE__{} = pattern, slot_id, opts \\ []) do
    configure_slot(pattern, slot_id, %{
      name: Keyword.get(opts, :name, "Drone"),
      synth: Keyword.get(opts, :synth, "pc_voice"),
      note: Keyword.get(opts, :note, 38),
      duration_ms: Keyword.get(opts, :duration_ms, 0),
      gain: Keyword.get(opts, :gain, 0.7),
      scale: Keyword.get(opts, :scale, @drone_voicing),
      trigger: %{kind: :held},
      channel: %{mode: :all_panels}
    })
  end

  @doc "Mutes or unmutes every slot at once."
  @spec mute_all(t(), boolean()) :: t()
  def mute_all(%__MODULE__{} = pattern, muted?) do
    %{pattern | slots: Enum.map(pattern.slots, &%{&1 | muted?: muted?})}
  end

  @doc """
  True when every slot is muted.

  Empty slots count: the studio's one button has to read the truth of what it
  did, and skipping them made it say "Alle stumm" on an already silent patch.
  """
  @spec all_muted?(t()) :: boolean()
  def all_muted?(%__MODULE__{slots: slots}), do: Enum.all?(slots, & &1.muted?)

  @doc """
  Mutes every slot.

  What panic does to the pattern: the engine is silenced anyway, but a trigger
  that keeps firing would bring the sound straight back. Muting is reversible,
  which deleting would not be.
  """
  @spec silence(t()) :: t()
  def silence(%__MODULE__{} = pattern) do
    %{pattern | slots: Enum.map(pattern.slots, &%{&1 | muted?: true})}
  end

  @doc "The first slot with nothing on it, for the one-click presets."
  @spec free_slot(t()) :: pos_integer() | nil
  def free_slot(%__MODULE__{slots: slots}) do
    case Enum.find(slots, &empty_slot?/1) do
      nil -> nil
      slot -> slot.id
    end
  end

  @doc "A slot nobody has given anything to do."
  @spec empty_slot?(slot()) :: boolean()
  def empty_slot?(slot), do: slot.trigger.kind == :grid and slot.steps == %{}

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

  @doc "Applies `attrs` to every slot the filter accepts."
  @spec configure_where(t(), (slot() -> boolean()), map()) :: t()
  def configure_where(%__MODULE__{} = pattern, filter, attrs) do
    Enum.reduce(pattern.slots, pattern, fn slot, pattern ->
      if filter.(slot), do: configure_slot(pattern, slot.id, attrs), else: pattern
    end)
  end

  @spec configure_slot(t(), pos_integer(), map()) :: t()
  def configure_slot(%__MODULE__{} = pattern, slot_id, attrs) do
    update_slot(pattern, slot_id, fn slot ->
      slot
      |> then(&Enum.reduce(attrs, &1, fn {key, value}, slot -> Map.replace(slot, key, value) end))
      |> then(&%{&1 | synth: valid_synth(&1)})
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
        slot: slot.id,
        channel: channel,
        note: pitch_for(slot, channel),
        velocity: cell.velocity * slot.gain,
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
            "gain" => slot.gain,
            "scale" => slot.scale,
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
      gain: slot["gain"] || 0.7,
      scale: scale_from_map(slot["scale"]),
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
        # A composition saved before the trigger could choose what to watch
        # kept firing on the value crossing zero, so that is what it reads as.
        %{
          kind: :probe,
          quantity: quantity_from_map(trigger["quantity"]),
          level: trigger["level"] || 0.0,
          min_rise: trigger["min_rise"] || @default_probe_trigger.min_rise,
          min_interval_ms: trigger["min_interval_ms"] || @default_probe_trigger.min_interval_ms
        }

      kind ->
        %{kind: kind}
    end
  end

  defp trigger_from_map(_other), do: @default_trigger

  defp quantity_from_map("brightness"), do: :brightness
  defp quantity_from_map("speed"), do: :speed
  defp quantity_from_map(_other), do: :value

  defp scale_from_map(scale) when is_list(scale) and scale != [], do: scale
  defp scale_from_map(_other), do: @default_scale

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
