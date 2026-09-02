defmodule Octopus.Sound.Matrix do
  @moduledoc """
  What moves what, slowly.

  The grid says when something sounds; the matrix says what drifts. Each row
  is one sentence: *this source moves this target by this much, along this
  curve.* The three coupling directions from `docs/pixelfun-av/01-konzept.md`
  are not three mechanisms — they are rows whose source and target happen to
  live in different worlds:

    * a **feature** moving a **scene** parameter is sound → light
    * a **probe** moving the drone or the chase is light → sound
    * a **phase** or **LFO** moving either is the score moving both

  Every source yields `0..1` and every target adds `amount × span × value` on
  top of the value it had when the row was made. Modulation only ever adds,
  which keeps a row readable: turn the amount up and the parameter goes up.
  """

  use GenServer

  alias Octopus.AppSupervisor
  alias Octopus.Sound.{Clock, Features, Patch, Pattern, Probes, Time, Timeline}
  alias Phoenix.PubSub

  @topic "sound_matrix"
  # Scene parameters travel to a running app as config updates; ten a second is
  # smooth to the eye and leaves the app alone the rest of the time.
  @interval_ms 100
  @epsilon 0.001

  @sources %{
    {:phase, 4} => %{label: "Phase · 4 Takte", domain: :score},
    {:phase, 8} => %{label: "Phase · 8 Takte", domain: :score},
    {:phase, 16} => %{label: "Phase · 16 Takte", domain: :score},
    {:lfo, 1} => %{label: "LFO · 1 Takt", domain: :score},
    {:lfo, 4} => %{label: "LFO · 4 Takte", domain: :score},
    {:probe, :mean} => %{label: "Probes · Mittel", domain: :light},
    {:probe, :max} => %{label: "Probes · Maximum", domain: :light},
    {:feature, :level} => %{label: "Klang · Pegel", domain: :sound},
    {:feature, :onset} => %{label: "Klang · Onsets", domain: :sound}
  }

  @targets %{
    {:scene, :zoom_base} => %{
      label: "Szene · Zoom",
      span: 2.0,
      min: 0.7,
      max: 11.0,
      domain: :light
    },
    {:scene, :saturation_percent} => %{
      label: "Szene · Sättigung",
      span: 45.0,
      min: 0.0,
      max: 100.0,
      domain: :light
    },
    {:scene, :brightness_percent} => %{
      label: "Szene · Helligkeit",
      span: 40.0,
      min: 0.0,
      max: 100.0,
      domain: :light
    },
    {:scene, :pattern_speed} => %{
      label: "Szene · Mustertempo",
      span: 1.5,
      min: 0.05,
      max: 5.0,
      domain: :light
    },
    {:held, :gain} => %{
      label: "Gehaltene Slots · Lautstärke",
      span: 0.8,
      min: 0.0,
      max: 1.2,
      domain: :sound
    },
    {:probe, :duration_ms} => %{
      label: "Probe-Slots · Länge",
      span: 900.0,
      min: 40.0,
      max: 2000.0,
      domain: :sound
    }
  }

  @curves [:linear, :exp, :inverse]

  # -- API ------------------------------------------------------------------

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def subscribe, do: PubSub.subscribe(Octopus.PubSub, @topic)

  def sources, do: @sources
  def targets, do: @targets
  def curves, do: @curves

  def list, do: GenServer.call(__MODULE__, :list)

  @doc "Adds a row. `source` and `target` are keys of `sources/0` and `targets/0`."
  def add(source, target, opts \\ []),
    do: GenServer.call(__MODULE__, {:add, source, target, opts})

  def remove(id), do: GenServer.call(__MODULE__, {:remove, id})
  def set_amount(id, amount), do: GenServer.call(__MODULE__, {:set_amount, id, amount})

  def set_curve(id, curve) when curve in @curves,
    do: GenServer.call(__MODULE__, {:curve, id, curve})

  def toggle(id), do: GenServer.call(__MODULE__, {:toggle, id})
  def clear, do: GenServer.call(__MODULE__, :clear)

  @doc """
  Which way a row couples, from where its source and target live.

  This is the whole trick: there is no separate machinery per direction.
  """
  @spec direction(any(), any()) :: :sound_to_light | :light_to_sound | :score | :within
  def direction(source, target) do
    from = get_in(@sources, [source, :domain])
    to = get_in(@targets, [target, :domain])

    case {from, to} do
      {:sound, :light} -> :sound_to_light
      {:light, :sound} -> :light_to_sound
      {:score, _} -> :score
      _ -> :within
    end
  end

  @doc "Value of a source in `0..1`, from a snapshot of the world."
  @spec value(any(), map()) :: float()
  def value({:phase, bars}, %{beats: beats, beats_per_bar: per_bar}) do
    # Triangle: out and back over the given number of bars, so a scene that
    # breathes returns to where it started instead of jumping back.
    phase = Integer.mod(floor(beats), per_bar * bars) + (beats - floor(beats))
    position = phase / (per_bar * bars)
    if position < 0.5, do: position * 2, else: (1 - position) * 2
  end

  def value({:lfo, bars}, %{beats: beats, beats_per_bar: per_bar}) do
    (:math.sin(2 * :math.pi() * beats / (per_bar * bars)) + 1) / 2
  end

  def value({:probe, :mean}, %{probes: []}), do: 0.5

  def value({:probe, :mean}, %{probes: probes}) do
    unipolar(Enum.sum(probes) / length(probes))
  end

  def value({:probe, :max}, %{probes: []}), do: 0.5
  def value({:probe, :max}, %{probes: probes}), do: unipolar(Enum.max(probes))

  def value({:feature, band}, %{features: features}), do: Map.get(features, band, 0.0)
  def value(_source, _context), do: 0.0

  @doc "Applies a curve to a `0..1` value."
  def shape(:linear, value), do: value
  def shape(:exp, value), do: value * value
  def shape(:inverse, value), do: 1.0 - value

  # -- Server ---------------------------------------------------------------

  @impl true
  def init(_opts) do
    Probes.subscribe()
    Features.subscribe()
    {:ok, _} = :timer.send_interval(@interval_ms, :apply)

    {:ok, %{bindings: [], next_id: 1, probes: [], features: %{}, applied: %{}}}
  end

  @impl true
  def handle_call(:list, _from, state), do: {:reply, state.bindings, state}

  def handle_call({:add, source, target, opts}, _from, state) do
    if Map.has_key?(@sources, source) and Map.has_key?(@targets, target) do
      binding = %{
        id: state.next_id,
        source: source,
        target: target,
        amount: Keyword.get(opts, :amount, 0.5),
        curve: Keyword.get(opts, :curve, :linear),
        enabled?: true,
        # Captured now: modulation adds to what the parameter was when the row
        # was made, so removing the row gives that value back.
        base: read_target(target)
      }

      {:reply, binding,
       announce(%{state | bindings: state.bindings ++ [binding], next_id: state.next_id + 1})}
    else
      {:reply, {:error, :unknown}, state}
    end
  end

  def handle_call({:remove, id}, _from, state) do
    {removed, kept} = Enum.split_with(state.bindings, &(&1.id == id))
    Enum.each(removed, &restore/1)

    {:reply, :ok, announce(%{state | bindings: kept})}
  end

  def handle_call({:set_amount, id, amount}, _from, state) do
    {:reply, :ok, announce(update(state, id, &%{&1 | amount: clamp(amount, 0.0, 1.0)}))}
  end

  def handle_call({:curve, id, curve}, _from, state) do
    {:reply, :ok, announce(update(state, id, &%{&1 | curve: curve}))}
  end

  def handle_call({:toggle, id}, _from, state) do
    state = update(state, id, &%{&1 | enabled?: not &1.enabled?})
    Enum.each(state.bindings, fn binding -> unless binding.enabled?, do: restore(binding) end)

    {:reply, :ok, announce(state)}
  end

  def handle_call(:clear, _from, state) do
    Enum.each(state.bindings, &restore/1)
    {:reply, :ok, announce(%{state | bindings: [], applied: %{}})}
  end

  @impl true
  def handle_info({:pixel_probes, %{values: values}}, state),
    do: {:noreply, %{state | probes: values}}

  def handle_info({:sound_features, features}, state),
    do: {:noreply, %{state | features: features}}

  def handle_info(:apply, %{bindings: []} = state), do: {:noreply, state}

  def handle_info(:apply, state) do
    context = context(state)

    applied =
      state.bindings
      |> Enum.filter(& &1.enabled?)
      |> Enum.group_by(& &1.target)
      |> Enum.reduce(state.applied, fn {target, bindings}, applied ->
        write(target, bindings, context, applied)
      end)

    {:noreply, %{state | applied: applied}}
  end

  def handle_info(_message, state), do: {:noreply, state}

  # -- Internals ------------------------------------------------------------

  defp context(state) do
    timeline = safe(&Clock.timeline/0, %Timeline{})

    %{
      beats: Timeline.beats_at(timeline, Time.now()),
      beats_per_bar: timeline.beats_per_bar,
      probes: state.probes,
      features: state.features
    }
  end

  defp write(target, bindings, context, applied) do
    spec = Map.fetch!(@targets, target)
    base = hd(bindings).base || spec.min

    delta =
      Enum.reduce(bindings, 0.0, fn binding, sum ->
        sum + binding.amount * spec.span * shape(binding.curve, value(binding.source, context))
      end)

    value = clamp(base + delta, spec.min, spec.max)

    # A parameter is only written when it actually moved — the app gets a
    # config update, and every open console redraws, so ten no-ops a second
    # would be rude.
    if changed?(Map.get(applied, target), value) do
      apply_target(target, value)
      Map.put(applied, target, value)
    else
      applied
    end
  end

  defp changed?(nil, _value), do: true
  defp changed?(previous, value), do: abs(value - previous) > @epsilon

  defp apply_target({:scene, key}, value) do
    case scene_app_id() do
      nil -> :ok
      app_id -> AppSupervisor.update_config(app_id, %{key => value})
    end
  end

  # Targets name a kind of slot rather than an instrument: there can be two
  # chases now, and a row that moved only one of them would be a puzzle.
  defp apply_target({:held, :gain}, value),
    do: configure_slots(&(&1.trigger.kind == :held), %{gain: value})

  defp apply_target({:probe, :duration_ms}, value),
    do: configure_slots(&(&1.trigger.kind == :probe), %{duration_ms: round(value)})

  defp configure_slots(filter, attrs) do
    safe(fn -> Patch.update(&Pattern.configure_where(&1, filter, attrs)) end, :ok)
    :ok
  end

  defp read_target({:scene, key}) do
    case scene_app_id() do
      nil -> nil
      app_id -> app_id |> AppSupervisor.config() |> Map.get(key)
    end
  end

  defp read_target({:held, :gain}), do: first_slot_value(:held, :gain)
  defp read_target({:probe, :duration_ms}), do: first_slot_value(:probe, :duration_ms)

  defp first_slot_value(kind, key) do
    safe(
      fn ->
        Patch.pattern().slots
        |> Enum.find(&(&1.trigger.kind == kind))
        |> case do
          nil -> nil
          slot -> Map.get(slot, key)
        end
      end,
      nil
    )
  end

  # Putting a parameter back where it was is the least surprising thing a
  # removed row can do — otherwise the scene silently keeps the last value.
  defp restore(%{target: target, base: base}) when not is_nil(base),
    do: apply_target(target, base)

  defp restore(_binding), do: :ok

  defp scene_app_id do
    Enum.find_value(AppSupervisor.running_apps(), fn
      {module, app_id} -> if module == Octopus.Apps.PixelFun, do: app_id
    end)
  rescue
    _ -> nil
  end

  defp update(state, id, fun) do
    %{
      state
      | bindings:
          Enum.map(state.bindings, fn
            %{id: ^id} = binding -> fun.(binding)
            binding -> binding
          end)
    }
  end

  defp announce(state) do
    if Process.whereis(Octopus.PubSub) do
      PubSub.broadcast(Octopus.PubSub, @topic, {:sound_matrix, state.bindings})
    end

    state
  end

  defp unipolar(value), do: clamp((value + 1) / 2, 0.0, 1.0)

  defp clamp(value, min, max), do: value |> max(min) |> min(max)

  defp safe(fun, fallback) do
    fun.()
  rescue
    _ -> fallback
  catch
    :exit, _ -> fallback
  end
end
