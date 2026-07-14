defmodule Octopus.Apps.Collective do
  @moduledoc """
  Collective — animations driven by the crowd's movement and position data.

  Consumes the radar PubSub feed (`Octopus.Radar.subscribe/0`,
  `{:radar_frame, device_id, %Octopus.Radar.Frame{}}`). In dev that feed is
  produced by the mock radar (`Octopus.Radar.Mock.World`/`Mock.Server`, boot
  mode `:exact` for the "dev" setup), which also drives the people shown in the
  3D sim — so the sim and these animations react to the exact same crowd. With
  real hardware on the same topic, this app keeps working unchanged.

  The app owns a fixed-rate render tick (decoupled from the radar frame rate) and
  hands the latest people to the selected animation (`Octopus.Apps.Collective.Animation`).
  """

  use Octopus.App, category: :animation

  alias Octopus.Canvas
  alias Octopus.Radar
  alias Octopus.Radar.Frame
  alias Octopus.Radar.Mock.World
  alias Octopus.Apps.Collective.Animations

  @fps 30
  @max_dt 0.1
  @track_stale_ms 1500

  # Maps the :select config value to the animation module.
  @animations %{
    storm: Animations.Storm,
    breath: Animations.Breath,
    dots: Animations.Dots,
    orbital: Animations.Orbital,
    lava_lamp: Animations.LavaLamp,
    ring_noise: Animations.RingNoise,
    presence: Animations.PresencePanels
  }

  def name, do: "Collective"

  @mode_labels %{
    storm: "Storm",
    breath: "Breath",
    dots: "Dots",
    orbital: "Orbital drift",
    lava_lamp: "Lava lamp",
    ring_noise: "Ring noise",
    presence: "Presence"
  }

  @mode_accents %{
    storm: "#E74C3C",
    breath: "#3498DB",
    dots: "#F1C40F",
    orbital: "#9B59B6",
    lava_lamp: "#E67E22",
    ring_noise: "#1ABC9C",
    presence: "#2ECC71"
  }

  @mode_presets Module.concat(["Octopus", "AppModePresets"])

  def list_modes do
    apply(@mode_presets, :list_modes, [__MODULE__])
  end

  def mode_config(mode_id) do
    (apply(@mode_presets, :config_for, [__MODULE__, mode_id]) ||
       legacy_mode_config(apply(@mode_presets, :mode_slug, [mode_id])))
    |> normalize_mode_config()
  end

  def normalize_mode_config(config), do: coerce_config_atoms(config)

  def mode_tweakables(mode_id) do
    mode_tweakables_for(apply(@mode_presets, :mode_slug, [mode_id]))
  end

  def builtin_presets do
    Enum.map(@animations, fn {key, _mod} ->
      slug = Atom.to_string(key)

      %{
        slug: slug,
        name: Map.fetch!(@mode_labels, key),
        accent_color: Map.fetch!(@mode_accents, key),
        config: legacy_mode_config(slug)
      }
    end)
  end

  def legacy_mode_config(slug) do
    case slug do
      "storm" ->
        %{animation: :storm, background: :deep_dark, sensitivity: 1.0}

      "breath" ->
        %{
          animation: :breath,
          breath_liveliness: 0.25,
          breath_layout: :wave,
          breath_palette: :ocean,
          breath_hue_shift: 0.0
        }

      "dots" ->
        %{animation: :dots, dots_smoothing: 0.35}

      "orbital" ->
        %{animation: :orbital, orbital_liveliness: 0.35, orbital_sun_gain: 1.0}

      "lava_lamp" ->
        %{
          animation: :lava_lamp,
          lava_blob_count: 7,
          lava_speed: 1.0,
          lava_size_mul: 1.25,
          lava_thresh: 0.9,
          lava_palette: :classic,
          lava_reactivity: 0.6,
          lava_warmth: 0.5,
          lava_people_blobs: true
        }

      "ring_noise" ->
        %{
          animation: :ring_noise,
          ring_noise_speed: 1.0,
          ring_noise_pulse_period: 24.0,
          ring_noise_pulse_amount: 0.65,
          ring_noise_counter_wave: true,
          ring_noise_palette: :lava
        }

      "presence" ->
        %{
          animation: :presence,
          presence_floor: 0.0,
          presence_bleed: 0.35
        }

      _ ->
        %{}
    end
  end

  def mode_tweakables_for("storm") do
    [
      %{
        key: :sensitivity,
        label: "Storm sensitivity",
        type: :slider,
        min: 0.2,
        max: 3.0,
        step: 0.1,
        default: 1.0
      },
      %{
        key: :background,
        label: "Background",
        type: :choice,
        default: :deep_dark,
        options: [{:deep_dark, "Deep dark"}, {:still_stars, "Still stars"}]
      }
    ]
  end

  def mode_tweakables_for("breath") do
    [
      %{
        key: :breath_liveliness,
        label: "Liveliness",
        type: :slider,
        min: 0.0,
        max: 1.0,
        step: 0.05,
        default: 0.25
      },
      %{
        key: :breath_layout,
        label: "Layout",
        type: :choice,
        default: :wave,
        options: [{:wave, "Wave"}, {:canopy, "Canopy"}]
      },
      %{
        key: :breath_palette,
        label: "Palette",
        type: :choice,
        default: :ocean,
        options: [
          {:ocean, "Ocean"},
          {:ember, "Ember"},
          {:aurora, "Aurora"},
          {:violet, "Violet"},
          {:mono, "Mono"}
        ]
      }
    ]
  end

  def mode_tweakables_for("dots") do
    [
      %{
        key: :dots_smoothing,
        label: "Dot smoothing",
        type: :slider,
        min: 0.0,
        max: 1.0,
        step: 0.05,
        default: 0.35
      }
    ]
  end

  def mode_tweakables_for("orbital") do
    [
      %{
        key: :orbital_liveliness,
        label: "Liveliness",
        type: :slider,
        min: 0.0,
        max: 1.0,
        step: 0.05,
        default: 0.35
      },
      %{
        key: :orbital_sun_gain,
        label: "Sun gain",
        type: :slider,
        min: 0.2,
        max: 2.5,
        step: 0.05,
        default: 1.0
      }
    ]
  end

  def mode_tweakables_for("lava_lamp") do
    [
      %{
        key: :lava_reactivity,
        label: "Crowd heat",
        type: :slider,
        min: 0.0,
        max: 1.0,
        step: 0.05,
        default: 0.6,
        runtime: true
      },
      %{
        key: :lava_speed,
        label: "Speed",
        type: :slider,
        min: 0.2,
        max: 3.0,
        step: 0.05,
        default: 1.0,
        runtime: true
      },
      %{
        key: :lava_warmth,
        label: "Warmth",
        type: :slider,
        min: 0.0,
        max: 1.0,
        step: 0.05,
        default: 0.5,
        runtime: true
      },
      %{
        key: :lava_people_blobs,
        label: "People as blobs",
        type: :toggle,
        default: true,
        runtime: true
      },
      %{
        key: :lava_palette,
        label: "Palette",
        type: :choice,
        default: :classic,
        options: [{:classic, "Classic"}, {:magenta, "Magenta"}, {:slime, "Slime"}]
      }
    ]
  end

  def mode_tweakables_for("ring_noise") do
    [
      %{
        key: :ring_noise_speed,
        label: "Noise speed",
        type: :slider,
        min: 0.0,
        max: 3.0,
        step: 0.05,
        default: 1.0
      },
      %{
        key: :ring_noise_palette,
        label: "Palette",
        type: :choice,
        default: :lava,
        options: [{:lava, "Lava"}, {:ocean, "Ocean"}, {:aurora, "Aurora"}]
      },
      %{
        key: :ring_noise_counter_wave,
        label: "Counter wave",
        type: :toggle,
        default: true
      }
    ]
  end

  def mode_tweakables_for("presence") do
    [
      %{
        key: :presence_floor,
        label: "Base glow",
        type: :slider,
        min: 0.0,
        max: 0.4,
        step: 0.02,
        default: 0.0
      },
      %{
        key: :presence_bleed,
        label: "Neighbour bleed",
        type: :slider,
        min: 0.0,
        max: 0.7,
        step: 0.05,
        default: 0.35
      }
    ]
  end

  def mode_tweakables_for(_mode_id), do: []

  def apply_mode(app_id, mode_id) do
    Octopus.AppSupervisor.update_config(app_id, mode_config(mode_id))
  end

  def app_init(config) do
    # Instant panel updates — easing on the firmware side never completes when every
    # pixel changes every frame (Lava Lamp / Ring Noise) and can freeze the panel.
    Octopus.App.configure_display(layout: :adjacent_panels, easing_interval: 0)
    display_info = Octopus.App.get_display_info()

    Radar.subscribe()
    Phoenix.PubSub.subscribe(Octopus.PubSub, World.world_topic())

    sensitivity = Map.get(config, :sensitivity, 1.0)
    breath_liveliness = Map.get(config, :breath_liveliness, 0.25)
    breath_palette = Map.get(config, :breath_palette, :ocean)
    breath_hue_shift = Map.get(config, :breath_hue_shift, 0.0)
    breath_layout = Map.get(config, :breath_layout, :wave)
    dots_smoothing = Map.get(config, :dots_smoothing, 0.35)
    orbital_liveliness = Map.get(config, :orbital_liveliness, 0.35)
    orbital_sun_gain = Map.get(config, :orbital_sun_gain, 1.0)
    lava_blob_count = Map.get(config, :lava_blob_count, 7)
    lava_speed = Map.get(config, :lava_speed, 1.0)
    lava_size_mul = Map.get(config, :lava_size_mul, 1.25)
    lava_thresh = Map.get(config, :lava_thresh, 0.9)
    lava_palette = Map.get(config, :lava_palette, :classic)
    lava_reactivity = Map.get(config, :lava_reactivity, 0.6)
    lava_warmth = Map.get(config, :lava_warmth, 0.5)
    lava_people_blobs = Map.get(config, :lava_people_blobs, true)
    ring_noise_speed = Map.get(config, :ring_noise_speed, 1.0)
    ring_noise_pulse_period = Map.get(config, :ring_noise_pulse_period, 24.0)
    ring_noise_pulse_amount = Map.get(config, :ring_noise_pulse_amount, 0.65)
    ring_noise_counter_wave = Map.get(config, :ring_noise_counter_wave, true)
    ring_noise_palette = Map.get(config, :ring_noise_palette, :lava)
    presence_floor = Map.get(config, :presence_floor, 0.0)
    presence_bleed = Map.get(config, :presence_bleed, 0.35)
    background = Map.get(config, :background, :deep_dark) |> coerce_atom(:deep_dark)
    animation = Map.get(config, :animation, :storm) |> coerce_atom(:storm)
    anim_mod = Map.fetch!(@animations, animation)

    Process.send_after(self(), :tick, 0)

    state = %{
      canvas: Canvas.new(display_info.width, display_info.height),
      display_info: display_info,
      track_registry: %{},
      sensitivity: sensitivity,
      breath_liveliness: breath_liveliness,
      breath_palette: breath_palette,
      breath_hue_shift: breath_hue_shift,
      breath_layout: breath_layout,
      dots_smoothing: dots_smoothing,
      orbital_liveliness: orbital_liveliness,
      orbital_sun_gain: orbital_sun_gain,
      lava_blob_count: lava_blob_count,
      lava_speed: lava_speed,
      lava_size_mul: lava_size_mul,
      lava_thresh: lava_thresh,
      lava_palette: lava_palette,
      lava_reactivity: lava_reactivity,
      lava_warmth: lava_warmth,
      lava_people_blobs: lava_people_blobs,
      ring_noise_speed: ring_noise_speed,
      ring_noise_pulse_period: ring_noise_pulse_period,
      ring_noise_pulse_amount: ring_noise_pulse_amount,
      ring_noise_counter_wave: ring_noise_counter_wave,
      ring_noise_palette: ring_noise_palette,
      presence_floor: presence_floor,
      presence_bleed: presence_bleed,
      background: background,
      animation: animation,
      anim_mod: anim_mod,
      anim_state: anim_mod.init(display_info),
      last_update: now_ms()
    }

    {:ok, state}
  end

  def handle_info({:mock_world, objects}, state) when is_list(objects) and objects != [] do
    now = :erlang.monotonic_time(:millisecond)

    track_registry =
      Map.new(objects, fn obj ->
        person = object_to_person(obj)
        {person.id, {person, now}}
      end)

    {:noreply, %{state | track_registry: track_registry}}
  end

  def handle_info({:mock_world, _objects}, state), do: {:noreply, state}

  def handle_info({:radar_frame, device_id, %Frame{tracks: tracks}}, state) do
    now = :erlang.monotonic_time(:millisecond)
    track_registry = Map.get(state, :track_registry, %{})

    track_registry =
      Enum.reduce(tracks, track_registry, fn track, acc ->
        person = track_to_person(track, device_id)
        Map.put(acc, person.id, {person, now})
      end)

    {:noreply, %{state | track_registry: track_registry}}
  end

  def handle_info(:tick, state) do
    tick_start = now_ms()
    now = tick_start
    dt = (max(now - state.last_update, 0) / 1000.0) |> min(@max_dt)
    people = fetch_people(state, now)

    ctx = %{
      dt: dt,
      sensitivity: state.sensitivity,
      breath_liveliness: state.breath_liveliness,
      breath_palette: state.breath_palette,
      breath_hue_shift: state.breath_hue_shift,
      breath_layout: state.breath_layout,
      dots_smoothing: state.dots_smoothing,
      orbital_liveliness: state.orbital_liveliness,
      orbital_sun_gain: state.orbital_sun_gain,
      lava_blob_count: state.lava_blob_count,
      lava_speed: state.lava_speed,
      lava_size_mul: state.lava_size_mul,
      lava_thresh: state.lava_thresh,
      lava_palette: state.lava_palette,
      lava_reactivity: state.lava_reactivity,
      lava_warmth: state.lava_warmth,
      lava_people_blobs: state.lava_people_blobs,
      ring_noise_speed: state.ring_noise_speed,
      ring_noise_pulse_period: state.ring_noise_pulse_period,
      ring_noise_pulse_amount: state.ring_noise_pulse_amount,
      ring_noise_counter_wave: state.ring_noise_counter_wave,
      ring_noise_palette: state.ring_noise_palette,
      presence_floor: state.presence_floor,
      presence_bleed: state.presence_bleed,
      background: state.background,
      display_info: state.display_info
    }

    {canvas, anim_state} =
      Canvas.new(state.display_info.width, state.display_info.height)
      |> state.anim_mod.render(people, ctx, state.anim_state)

    Octopus.App.update_display(canvas)

    elapsed = now_ms() - tick_start
    Process.send_after(self(), :tick, max(frame_ms() - elapsed, 1))

    {:noreply, %{state | canvas: canvas, anim_state: anim_state, last_update: now}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # Keyword list => the config UI renders in this exact order (Animation first).
  # `visible_when: {:animation, [...]}` hides storm-only options unless Tempest
  # is selected.
  def config_schema do
    [
      animation:
        {"Animation", :select,
         %{
           default: 0,
           options: [
             {"Tempest", :storm},
             {"Crowd Breath", :breath},
             {"Crowd Dots", :dots},
             {"Orbital", :orbital},
             {"Lava Lamp", :lava_lamp},
             {"Ring Noise", :ring_noise},
             {"Presence", :presence}
           ]
         }},
      background:
        {"Background", :select,
         %{
           default: 0,
           options: [{"Deep Dark", :deep_dark}, {"Still Stars", :still_stars}],
           visible_when: {:animation, [:storm]}
         }},
      sensitivity:
        {"Storm Sensitivity", :float,
         %{min: 0.2, max: 3.0, default: 1.0, visible_when: {:animation, [:storm]}}},
      breath_liveliness:
        {"Breath Liveliness", :float,
         %{
           min: 0.0,
           max: 1.0,
           default: 0.25,
           step: 0.05,
           visible_when: {:animation, [:breath]}
         }},
      breath_layout:
        {"Breath Layout", :select,
         %{
           default: 0,
           options: [{"Wave", :wave}, {"Canopy", :canopy}],
           visible_when: {:animation, [:breath]}
         }},
      breath_palette:
        {"Breath Palette", :select,
         %{
           default: 0,
           options: [
             {"Ocean", :ocean},
             {"Ember", :ember},
             {"Aurora", :aurora},
             {"Violet", :violet},
             {"Mono", :mono}
           ],
           visible_when: {:animation, [:breath]}
         }},
      breath_hue_shift:
        {"Breath Hue Shift", :float,
         %{
           min: 0.0,
           max: 1.0,
           default: 0.0,
           step: 0.02,
           visible_when: {:animation, [:breath]}
         }},
      dots_smoothing:
        {"Dot Smoothing", :float,
         %{
           min: 0.0,
           max: 1.0,
           default: 0.35,
           step: 0.05,
           visible_when: {:animation, [:dots]}
         }},
      orbital_liveliness:
        {"Orbital Liveliness", :float,
         %{
           min: 0.0,
           max: 1.0,
           default: 0.35,
           step: 0.05,
           visible_when: {:animation, [:orbital]}
         }},
      orbital_sun_gain:
        {"Sun Gain", :float,
         %{
           min: 0.2,
           max: 2.5,
           default: 1.0,
           step: 0.05,
           visible_when: {:animation, [:orbital]}
         }},
      lava_blob_count:
        {"Blob Count", :int,
         %{
           min: 3,
           max: 12,
           default: 7,
           visible_when: {:animation, [:lava_lamp]}
         }},
      lava_speed:
        {"Speed", :float,
         %{
           min: 0.2,
           max: 3.0,
           default: 1.0,
           step: 0.05,
           visible_when: {:animation, [:lava_lamp]}
         }},
      lava_size_mul:
        {"Size", :float,
         %{
           min: 0.6,
           max: 2.2,
           default: 1.25,
           step: 0.05,
           visible_when: {:animation, [:lava_lamp]}
         }},
      lava_thresh:
        {"Threshold", :float,
         %{
           min: 0.4,
           max: 1.6,
           default: 0.9,
           step: 0.05,
           visible_when: {:animation, [:lava_lamp]}
         }},
      lava_palette:
        {"Palette", :select,
         %{
           default: 0,
           options: [
             {"Classic", :classic},
             {"Magenta", :magenta},
             {"Slime", :slime}
           ],
           visible_when: {:animation, [:lava_lamp]}
         }},
      lava_reactivity:
        {"Crowd Heat", :float,
         %{
           min: 0.0,
           max: 1.0,
           default: 0.6,
           step: 0.05,
           visible_when: {:animation, [:lava_lamp]}
         }},
      lava_warmth:
        {"Warmth", :float,
         %{
           min: 0.0,
           max: 1.0,
           default: 0.5,
           step: 0.05,
           visible_when: {:animation, [:lava_lamp]}
         }},
      lava_people_blobs:
        {"People as Blobs", :boolean, %{default: true, visible_when: {:animation, [:lava_lamp]}}},
      ring_noise_speed:
        {"Noise Speed", :float,
         %{
           min: 0.0,
           max: 3.0,
           default: 1.0,
           step: 0.05,
           visible_when: {:animation, [:ring_noise]}
         }},
      ring_noise_pulse_period:
        {"Pulse Period", :float,
         %{
           min: 4.0,
           max: 120.0,
           default: 24.0,
           step: 1.0,
           visible_when: {:animation, [:ring_noise]}
         }},
      ring_noise_pulse_amount:
        {"Pulse Amount", :float,
         %{
           min: 0.0,
           max: 1.0,
           default: 0.65,
           step: 0.05,
           visible_when: {:animation, [:ring_noise]}
         }},
      ring_noise_counter_wave:
        {"Counter Wave", :boolean, %{default: true, visible_when: {:animation, [:ring_noise]}}},
      ring_noise_palette:
        {"Palette", :select,
         %{
           default: 0,
           options: [
             {"Lava", :lava},
             {"Ocean", :ocean},
             {"Aurora", :aurora}
           ],
           visible_when: {:animation, [:ring_noise]}
         }},
      presence_floor:
        {"Base Glow", :float,
         %{
           min: 0.0,
           max: 0.4,
           default: 0.0,
           step: 0.02,
           visible_when: {:animation, [:presence]}
         }},
      presence_bleed:
        {"Neighbour Bleed", :float,
         %{
           min: 0.0,
           max: 0.7,
           default: 0.35,
           step: 0.05,
           visible_when: {:animation, [:presence]}
         }}
    ]
  end

  # Field-test cheat sheet: how the selected animation reads the radar feed.
  # Rendered under the config form and refreshed whenever the config changes.
  def config_info(%{animation: :storm}) do
    """
    Tempest — per-person lightning + entry meteors.
    Reads POSITION and VELOCITY. Fast movement → bolts at that column. Someone
    crossing inward into the 20 m-diameter ring (10 m radius, = aframe panel ring)
    → a pale yellow shooting star on the opposite panel. Not on new track IDs /
    spawns already inside.
    • Storm Sensitivity — scales bolt probability for a given speed (higher = more).
    • Background — Deep Dark (black) or Still Stars (starfield + wandering moon
      that cycles new→full→new, plus 1–2 blinking satellites).
    """
  end

  def config_info(%{animation: :breath}) do
    """
    Crowd Breath — wave + local colour.
    Wave shape (level, height, flow) is global from two aggregates: head count
    (Density) and mean walking speed (Activity). Colour and its vertical depth
    gradient are LOCAL: each person tints the strip at their angular position
    (x/y → column, same mapping as Tempest) with a soft falloff (~±10 columns).
    gradient are LOCAL on the ring (r ≥ 2 m). People in the 2 m center chill disk
    have no column — in Canopy layout they drive the upper half instead.
    • Breath Layout — Wave (full strip) or Canopy (lower = ring palette, upper =
      neon yellow→white sky from center chillers).
    • Breath Liveliness — low = slow/smooth, high = faster + more reactive to walking.
    • Breath Palette — calm→hot on the ring only (Canopy sky is fixed bright yellow→white).
    • Breath Hue Shift — rotates the palette around the colour wheel (0 = as preset).
    """
  end

  def config_info(%{animation: :dots}) do
    """
    Crowd Dots — one pixel per person.
    X = angular position on the ring (dot wanders horizontally with the person).
    Y = distance from centre: at the ring / near the panels → bottom row;
    at the centre → top row. Stable colour per track id.
    After 3 s without movement, a soft ring pulse expands over ~3–4 panels and fades.
    • Dot Smoothing — low = snappy, high = soft follow (EMA on position).
    """
  end

  def config_info(%{animation: :orbital}) do
    """
    Orbital — crowd as a solar system.
    Center chillers (r < 2 m) drive a warm sun in the upper sky; more people and
    movement = brighter sun + downward rays. Ring walkers (r ≥ 2 m) appear as
    coloured comets on the lower strip (x = angle, y = radius). Groups of 3+
    within ~2.5 m merge into one larger planet. Background stars drift slightly
    with the ring crowd's angular balance.
    • Orbital Liveliness — low = slow/smooth follow, high = snappier motion + sun pulse.
    • Sun Gain — scales center brightness (higher = hotter sun).
    """
  end

  def config_info(%{animation: :lava_lamp}) do
    """
    Lava Lamp — cylindrical metaball blobs driven by crowd heat.
    Crowd activity (near the panels + walking counts more) heats the ring: hot
    zones lift and inflate blobs, speed up convection and warm the palette. Empty
    room = slow cold lamp. Crowd Heat 0 = classic crowd-blind decorative lava.
    • Crowd Heat — master crowd influence (0 = ignore the crowd).
    • Speed — base animation time scale (not frame rate).
    • Warmth — how much the palette cools when the room is empty.
    • People as Blobs — each person spawns a rising blob at their ring position.
    • Palette — Classic, Magenta, or Slime (hot end of the temperature axis).
    """
  end

  def config_info(%{animation: :ring_noise}) do
    """
    Ring Noise — seamless cylindrical noise field with palette colours and
    counter-rotating brightness waves. No crowd input.
    • Noise Speed — how fast the noise field evolves.
    • Pulse Period — seconds for one brightness wave lap around the ring.
    • Pulse Amount — mix between flat brightness and pulsing waves.
    • Counter Wave — second wave running the opposite direction.
    • Palette — Lava, Ocean, or Aurora colour stops.
    """
  end

  def config_info(%{animation: :presence}) do
    """
    Presence — each panel glows fully in a fixed random colour.
    Brightness follows the shared radar panel-activity service (crowd
    proximity, count, walking speed), with visual neighbour bleed and base
    glow applied here.
    • Base Glow — optional idle brightness (0 = black when inactive).
    • Neighbour Bleed — how much activity spills into adjacent panels.
    """
  end

  def config_info(_config), do: nil

  def now_playing_meta(config) do
    case config_info(config) do
      nil ->
        []

      text ->
        text
        |> String.split("\n", trim: true)
        |> Enum.take(2)
    end
  end

  def get_config(state) do
    %{
      animation: state.animation,
      background: state.background,
      sensitivity: state.sensitivity,
      breath_liveliness: state.breath_liveliness,
      breath_palette: state.breath_palette,
      breath_hue_shift: state.breath_hue_shift,
      breath_layout: state.breath_layout,
      dots_smoothing: state.dots_smoothing,
      orbital_liveliness: state.orbital_liveliness,
      orbital_sun_gain: state.orbital_sun_gain,
      lava_blob_count: state.lava_blob_count,
      lava_speed: state.lava_speed,
      lava_size_mul: state.lava_size_mul,
      lava_thresh: state.lava_thresh,
      lava_palette: state.lava_palette,
      lava_reactivity: state.lava_reactivity,
      lava_warmth: state.lava_warmth,
      lava_people_blobs: state.lava_people_blobs,
      ring_noise_speed: state.ring_noise_speed,
      ring_noise_pulse_period: state.ring_noise_pulse_period,
      ring_noise_pulse_amount: state.ring_noise_pulse_amount,
      ring_noise_counter_wave: state.ring_noise_counter_wave,
      ring_noise_palette: state.ring_noise_palette,
      presence_floor: state.presence_floor,
      presence_bleed: state.presence_bleed
    }
  end

  def handle_config(config, state) do
    config = coerce_config_atoms(config)
    animation = Map.get(config, :animation, state.animation)

    {anim_mod, anim_state, last_update} =
      if animation != state.animation do
        mod = Map.fetch!(@animations, animation)
        {mod, mod.init(state.display_info), now_ms()}
      else
        {state.anim_mod, state.anim_state, state.last_update}
      end

    {:noreply,
     %{
       state
       | animation: animation,
         anim_mod: anim_mod,
         anim_state: anim_state,
         last_update: last_update,
         background: Map.get(config, :background, state.background),
         sensitivity: Map.get(config, :sensitivity, state.sensitivity),
         breath_liveliness: Map.get(config, :breath_liveliness, state.breath_liveliness),
         breath_palette: Map.get(config, :breath_palette, state.breath_palette),
         breath_hue_shift: Map.get(config, :breath_hue_shift, state.breath_hue_shift),
         breath_layout: Map.get(config, :breath_layout, state.breath_layout),
         dots_smoothing: Map.get(config, :dots_smoothing, state.dots_smoothing),
         orbital_liveliness: Map.get(config, :orbital_liveliness, state.orbital_liveliness),
         orbital_sun_gain: Map.get(config, :orbital_sun_gain, state.orbital_sun_gain),
         lava_blob_count: Map.get(config, :lava_blob_count, state.lava_blob_count),
         lava_speed: Map.get(config, :lava_speed, state.lava_speed),
         lava_size_mul: Map.get(config, :lava_size_mul, state.lava_size_mul),
         lava_thresh: Map.get(config, :lava_thresh, state.lava_thresh),
         lava_palette: Map.get(config, :lava_palette, state.lava_palette),
         lava_reactivity: Map.get(config, :lava_reactivity, state.lava_reactivity),
         lava_warmth: Map.get(config, :lava_warmth, state.lava_warmth),
         lava_people_blobs: Map.get(config, :lava_people_blobs, state.lava_people_blobs),
         ring_noise_speed: Map.get(config, :ring_noise_speed, state.ring_noise_speed),
         ring_noise_pulse_period:
           Map.get(config, :ring_noise_pulse_period, state.ring_noise_pulse_period),
         ring_noise_pulse_amount:
           Map.get(config, :ring_noise_pulse_amount, state.ring_noise_pulse_amount),
         ring_noise_counter_wave:
           Map.get(config, :ring_noise_counter_wave, state.ring_noise_counter_wave),
         ring_noise_palette: Map.get(config, :ring_noise_palette, state.ring_noise_palette),
         presence_floor: Map.get(config, :presence_floor, state.presence_floor),
         presence_bleed: Map.get(config, :presence_bleed, state.presence_bleed)
     }}
  end

  defp fetch_people(state, now) do
    registry_people =
      active_people(Map.get(state, :track_registry, %{}), now, @track_stale_ms)

    case registry_people do
      [] -> mock_world_people()
      people -> people
    end
  end

  defp mock_world_people do
    case Process.whereis(World) do
      nil ->
        []

      _pid ->
        World.objects()
        |> Enum.map(&object_to_person/1)
    end
  rescue
    _ -> []
  end

  defp object_to_person(obj) do
    %{
      id: Map.get(obj, :id),
      x: Map.get(obj, :x, 0.0),
      y: Map.get(obj, :y, 0.0),
      vx: Map.get(obj, :vx, 0.0),
      vy: Map.get(obj, :vy, 0.0)
    }
  end

  defp track_to_person(track, device_id) do
    %{
      id: device_id * 10_000 + track.id,
      x: track.x,
      y: track.y,
      vx: track.vx,
      vy: track.vy
    }
  end

  defp active_people(track_registry, now, stale_ms) do
    track_registry
    |> Enum.filter(fn {_id, {_person, seen_at}} -> now - seen_at <= stale_ms end)
    |> Enum.map(fn {_id, {person, _seen_at}} -> person end)
  end

  defp now_ms, do: :erlang.monotonic_time(:millisecond)

  defp frame_ms do
    speed = Octopus.Installation.global_speed() |> max(0.1)
    trunc(1000 / (@fps * speed))
  end

  defp coerce_config_atoms(config) when is_map(config) do
    config
    |> Map.new(fn {k, v} -> {k, coerce_config_value(k, v)} end)
  end

  defp coerce_config_value(:animation, value), do: coerce_atom(value, :storm)
  defp coerce_config_value(:background, value), do: coerce_atom(value, :deep_dark)
  defp coerce_config_value(:breath_palette, value), do: coerce_atom(value, :ocean)
  defp coerce_config_value(:breath_layout, value), do: coerce_atom(value, :wave)
  defp coerce_config_value(:lava_palette, value), do: coerce_atom(value, :classic)
  defp coerce_config_value(:ring_noise_palette, value), do: coerce_atom(value, :lava)
  defp coerce_config_value(_key, value), do: value

  defp coerce_atom(value, _default) when is_atom(value), do: value

  defp coerce_atom(value, default) when is_binary(value) do
    case value do
      "true" -> true
      "false" -> false
      other -> String.to_existing_atom(other)
    end
  rescue
    ArgumentError -> default
  end

  defp coerce_atom(_value, default), do: default
end
