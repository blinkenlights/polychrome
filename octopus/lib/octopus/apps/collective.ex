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
  alias Octopus.Radar.TrackMerge
  alias Octopus.Apps.Collective.Animations

  @fps 30
  @max_dt 0.1
  @track_stale_ms 1500

  # Maps the :select config value to the animation module.
  @animations %{
    storm: Animations.Storm,
    breath: Animations.Breath,
    dots: Animations.Dots,
    lava_lamp: Animations.LavaLamp,
    fireflies: Animations.Fireflies,
    glowworms: Animations.Glowworms,
    ring_noise: Animations.RingNoise,
    presence: Animations.PresencePanels
  }

  def name, do: "Collective"

  @mode_presets Module.concat(["Octopus", "AppModePresets"])

  def list_modes do
    apply(@mode_presets, :list_modes, [__MODULE__])
  end

  def mode_config(mode_id) do
    (apply(@mode_presets, :config_for, [__MODULE__, mode_id]) || %{})
    |> normalize_mode_config()
  end

  def normalize_mode_config(config), do: coerce_config_atoms(config)

  def mode_tweakables(mode_id) do
    mode_tweakables_for(apply(@mode_presets, :mode_slug, [mode_id]))
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
        default: :still_stars,
        options: [{:deep_dark, "Deep dark"}, {:still_stars, "Still stars"}]
      },
      %{
        key: :storm_activity_bleed,
        label: "Activity bleed",
        type: :slider,
        min: 0.0,
        max: 0.5,
        step: 0.05,
        default: 0.2
      },
      %{
        key: :storm_reactivity,
        label: "Crowd heat",
        type: :slider,
        min: 0.0,
        max: 1.0,
        step: 0.05,
        default: 0.5
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
      },
      %{
        key: :dots_activity_bleed,
        label: "Activity bleed",
        type: :slider,
        min: 0.0,
        max: 0.5,
        step: 0.05,
        default: 0.2
      }
    ]
  end

  def mode_tweakables_for("fireflies") do
    [
      %{
        key: :firefly_reactivity,
        label: "Crowd heat",
        type: :slider,
        min: 0.0,
        max: 1.0,
        step: 0.05,
        default: 0.6,
        runtime: true
      },
      %{
        key: :firefly_speed,
        label: "Speed",
        type: :slider,
        min: 0.2,
        max: 2.0,
        step: 0.05,
        default: 1.5,
        runtime: true
      },
      %{
        key: :firefly_count,
        label: "Base count",
        type: :slider,
        min: 1,
        max: 40,
        step: 1,
        default: 24
      },
      %{
        key: :firefly_glow,
        label: "Glow",
        type: :slider,
        min: 0.5,
        max: 1.8,
        step: 0.05,
        default: 1.0,
        runtime: true
      },
      %{
        key: :firefly_flash_rate,
        label: "Breath depth",
        type: :slider,
        min: 0.4,
        max: 1.2,
        step: 0.05,
        default: 0.85,
        runtime: true
      },
      %{
        key: :firefly_palette,
        label: "Palette",
        type: :choice,
        default: :classic,
        options: [{:classic, "Classic"}, {:amber, "Amber"}, {:ghost, "Ghost"}]
      }
    ]
  end

  def mode_tweakables_for("glowworms") do
    [
      %{
        key: :glowworms_speed,
        label: "Glowworms Speed",
        type: :slider,
        min: 0.2,
        max: 5.0,
        step: 0.1,
        default: 1.6,
        runtime: true
      },
      %{
        key: :glowworms_color_intensity,
        label: "Color Intensity",
        type: :slider,
        min: 0.0,
        max: 1.0,
        step: 0.05,
        default: 0.55,
        runtime: true
      },
      %{
        key: :glowworms_max_count,
        label: "Max population of Glowworms",
        type: :slider,
        min: 1,
        max: 20,
        step: 1,
        default: 13,
        runtime: true
      },
      %{
        key: :glowworms_circling_area,
        label: "Glowworm circling area",
        type: :slider,
        min: 1,
        max: 10,
        step: 1,
        default: 4,
        runtime: true
      },
      %{
        key: :glowworms_stay_chance,
        label: "Stay Chance",
        type: :slider,
        min: 0.0,
        max: 1.0,
        step: 0.05,
        default: 0.5,
        runtime: true
      },
      %{
        key: :glowworms_run_away_proximity,
        label: "Run Away Proximity",
        type: :slider,
        min: 2,
        max: 10,
        step: 1,
        default: 5,
        runtime: true
      },
      %{
        key: :glowworms_run_away_count,
        label: "Run Away Count",
        type: :slider,
        min: 1,
        max: 10,
        step: 1,
        default: 3,
        runtime: true
      },
      %{
        key: :glowworms_run_away_duration,
        label: "Run Away Duration",
        type: :slider,
        min: 1,
        max: 10,
        step: 1,
        default: 5,
        runtime: true
      },
      %{
        key: :glowworms_gravity_stay_multiplier,
        label: "Gravity Stay Multiplier",
        type: :slider,
        min: 1.0,
        max: 10.0,
        step: 0.5,
        default: 3.0,
        runtime: true
      },
      %{
        key: :glowworms_birth_proximity_duration,
        label: "Birth Proximity Duration",
        type: :slider,
        min: 5,
        max: 60,
        step: 1,
        default: 30,
        runtime: true
      },
      %{
        key: :glowworms_overpopulation_death_duration,
        label: "Overpopulation Death Duration",
        type: :slider,
        min: 5,
        max: 120,
        step: 1,
        default: 45,
        runtime: true
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
        key: :lava_palette,
        label: "Palette",
        type: :choice,
        default: :classic,
        options: [{:classic, "Classic"}, {:magenta, "Magenta"}, {:slime, "Slime"}]
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

  def mode_tweakables_for("ring_noise"), do: ring_noise_tweakables()
  def mode_tweakables_for("ring_noise_brightness"), do: ring_noise_tweakables()
  def mode_tweakables_for("ring_noise_saturation"), do: ring_noise_tweakables()
  def mode_tweakables_for(_mode_id), do: []

  defp ring_noise_tweakables do
    [
      %{
        key: :ring_noise_crowd_mode,
        label: "Crowd mode",
        type: :choice,
        default: :off,
        options: [{:off, "Off"}, {:brightness, "Brightness"}, {:saturation, "Saturation"}]
      },
      %{
        key: :ring_noise_reactivity,
        label: "Crowd heat",
        type: :slider,
        min: 0.0,
        max: 1.0,
        step: 0.05,
        default: 0.0
      },
      %{
        key: :ring_noise_crowd_gain,
        label: "Boost",
        type: :slider,
        min: 0.2,
        max: 2.0,
        step: 0.05,
        default: 1.0
      },
      %{
        key: :ring_noise_sat_idle,
        label: "Idle saturation",
        type: :slider,
        min: 0.0,
        max: 0.5,
        step: 0.02,
        default: 0.22
      },
      %{
        key: :ring_noise_activity_bleed,
        label: "Activity bleed",
        type: :slider,
        min: 0.0,
        max: 0.7,
        step: 0.05,
        default: 0.3
      },
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

  def apply_mode(app_id, mode_id) do
    Octopus.AppSupervisor.update_config(app_id, mode_config(mode_id))
  end

  def app_init(config) do
    # Instant panel updates — easing on the firmware side never completes when every
    # pixel changes every frame (Lava Lamp / Ring Noise) and can freeze the panel.
    Octopus.App.configure_display(
      layout: :adjacent_panels,
      easing_interval: 0,
      supports_grayscale: true,
      merge_rgbw: true
    )
    display_info = Octopus.App.get_display_info()

    Radar.subscribe()
    Phoenix.PubSub.subscribe(Octopus.PubSub, World.world_topic())

    sensitivity = Map.get(config, :sensitivity, 1.0)
    storm_activity_bleed = Map.get(config, :storm_activity_bleed, 0.2)
    storm_reactivity = Map.get(config, :storm_reactivity, 0.5)
    breath_liveliness = Map.get(config, :breath_liveliness, 0.25)
    breath_palette = Map.get(config, :breath_palette, :ocean)
    breath_hue_shift = Map.get(config, :breath_hue_shift, 0.0)
    breath_layout = Map.get(config, :breath_layout, :wave)
    dots_smoothing = Map.get(config, :dots_smoothing, 0.35)
    dots_activity_bleed = Map.get(config, :dots_activity_bleed, 0.2)
    lava_blob_count = Map.get(config, :lava_blob_count, 7)
    lava_speed = Map.get(config, :lava_speed, 1.0)
    lava_size_mul = Map.get(config, :lava_size_mul, 1.25)
    lava_thresh = Map.get(config, :lava_thresh, 0.9)
    lava_palette = Map.get(config, :lava_palette, :classic)
    lava_reactivity = Map.get(config, :lava_reactivity, 0.6)
    lava_warmth = Map.get(config, :lava_warmth, 0.5)
    firefly_count = Map.get(config, :firefly_count, 24)
    firefly_speed = Map.get(config, :firefly_speed, 1.5)
    firefly_reactivity = Map.get(config, :firefly_reactivity, 0.6)
    firefly_glow = Map.get(config, :firefly_glow, 1.0)
    firefly_flash_rate = Map.get(config, :firefly_flash_rate, 0.85)
    firefly_palette = Map.get(config, :firefly_palette, :classic)
    glowworms_speed = Map.get(config, :glowworms_speed, 1.6)
    glowworms_color_intensity = Map.get(config, :glowworms_color_intensity, 0.55)
    glowworms_max_count = Map.get(config, :glowworms_max_count, 13)
    glowworms_circling_area = Map.get(config, :glowworms_circling_area, 4)
    glowworms_stay_chance = Map.get(config, :glowworms_stay_chance, 0.5)
    glowworms_run_away_proximity = Map.get(config, :glowworms_run_away_proximity, 5)
    glowworms_run_away_count = Map.get(config, :glowworms_run_away_count, 3)
    glowworms_run_away_duration = Map.get(config, :glowworms_run_away_duration, 5)
    glowworms_gravity_stay_multiplier = Map.get(config, :glowworms_gravity_stay_multiplier, 3.0)
    glowworms_birth_proximity_duration = Map.get(config, :glowworms_birth_proximity_duration, 30)

    glowworms_overpopulation_death_duration =
      Map.get(config, :glowworms_overpopulation_death_duration, 45)

    ring_noise_speed = Map.get(config, :ring_noise_speed, 1.0)
    ring_noise_pulse_period = Map.get(config, :ring_noise_pulse_period, 24.0)
    ring_noise_pulse_amount = Map.get(config, :ring_noise_pulse_amount, 0.65)
    ring_noise_counter_wave = Map.get(config, :ring_noise_counter_wave, true)
    ring_noise_palette = Map.get(config, :ring_noise_palette, :lava)
    ring_noise_crowd_mode = Map.get(config, :ring_noise_crowd_mode, :off) |> coerce_atom(:off)
    ring_noise_reactivity = Map.get(config, :ring_noise_reactivity, 0.0)
    ring_noise_crowd_gain = Map.get(config, :ring_noise_crowd_gain, 1.0)
    ring_noise_sat_idle = Map.get(config, :ring_noise_sat_idle, 0.22)
    ring_noise_activity_bleed = Map.get(config, :ring_noise_activity_bleed, 0.3)
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
      storm_activity_bleed: storm_activity_bleed,
      storm_reactivity: storm_reactivity,
      breath_liveliness: breath_liveliness,
      breath_palette: breath_palette,
      breath_hue_shift: breath_hue_shift,
      breath_layout: breath_layout,
      dots_smoothing: dots_smoothing,
      dots_activity_bleed: dots_activity_bleed,
      lava_blob_count: lava_blob_count,
      lava_speed: lava_speed,
      lava_size_mul: lava_size_mul,
      lava_thresh: lava_thresh,
      lava_palette: lava_palette,
      lava_reactivity: lava_reactivity,
      lava_warmth: lava_warmth,
      firefly_count: firefly_count,
      firefly_speed: firefly_speed,
      firefly_reactivity: firefly_reactivity,
      firefly_glow: firefly_glow,
      firefly_flash_rate: firefly_flash_rate,
      firefly_palette: firefly_palette,
      glowworms_speed: glowworms_speed,
      glowworms_color_intensity: glowworms_color_intensity,
      glowworms_max_count: glowworms_max_count,
      glowworms_circling_area: glowworms_circling_area,
      glowworms_stay_chance: glowworms_stay_chance,
      glowworms_run_away_proximity: glowworms_run_away_proximity,
      glowworms_run_away_count: glowworms_run_away_count,
      glowworms_run_away_duration: glowworms_run_away_duration,
      glowworms_gravity_stay_multiplier: glowworms_gravity_stay_multiplier,
      glowworms_birth_proximity_duration: glowworms_birth_proximity_duration,
      glowworms_overpopulation_death_duration: glowworms_overpopulation_death_duration,
      ring_noise_speed: ring_noise_speed,
      ring_noise_pulse_period: ring_noise_pulse_period,
      ring_noise_pulse_amount: ring_noise_pulse_amount,
      ring_noise_counter_wave: ring_noise_counter_wave,
      ring_noise_palette: ring_noise_palette,
      ring_noise_crowd_mode: ring_noise_crowd_mode,
      ring_noise_reactivity: ring_noise_reactivity,
      ring_noise_crowd_gain: ring_noise_crowd_gain,
      ring_noise_sat_idle: ring_noise_sat_idle,
      ring_noise_activity_bleed: ring_noise_activity_bleed,
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
      storm_activity_bleed: state.storm_activity_bleed,
      storm_reactivity: state.storm_reactivity,
      breath_liveliness: state.breath_liveliness,
      breath_palette: state.breath_palette,
      breath_hue_shift: state.breath_hue_shift,
      breath_layout: state.breath_layout,
      dots_smoothing: state.dots_smoothing,
      dots_activity_bleed: state.dots_activity_bleed,
      lava_blob_count: state.lava_blob_count,
      lava_speed: state.lava_speed,
      lava_size_mul: state.lava_size_mul,
      lava_thresh: state.lava_thresh,
      lava_palette: state.lava_palette,
      lava_reactivity: state.lava_reactivity,
      lava_warmth: state.lava_warmth,
      firefly_count: state.firefly_count,
      firefly_speed: state.firefly_speed,
      firefly_reactivity: state.firefly_reactivity,
      firefly_glow: state.firefly_glow,
      firefly_flash_rate: state.firefly_flash_rate,
      firefly_palette: state.firefly_palette,
      glowworms_speed: state.glowworms_speed,
      glowworms_color_intensity: state.glowworms_color_intensity,
      glowworms_max_count: state.glowworms_max_count,
      glowworms_circling_area: state.glowworms_circling_area,
      glowworms_stay_chance: state.glowworms_stay_chance,
      glowworms_run_away_proximity: state.glowworms_run_away_proximity,
      glowworms_run_away_count: state.glowworms_run_away_count,
      glowworms_run_away_duration: state.glowworms_run_away_duration,
      glowworms_gravity_stay_multiplier: state.glowworms_gravity_stay_multiplier,
      glowworms_birth_proximity_duration: state.glowworms_birth_proximity_duration,
      glowworms_overpopulation_death_duration: state.glowworms_overpopulation_death_duration,
      ring_noise_speed: state.ring_noise_speed,
      ring_noise_pulse_period: state.ring_noise_pulse_period,
      ring_noise_pulse_amount: state.ring_noise_pulse_amount,
      ring_noise_counter_wave: state.ring_noise_counter_wave,
      ring_noise_palette: state.ring_noise_palette,
      ring_noise_crowd_mode: state.ring_noise_crowd_mode,
      ring_noise_reactivity: state.ring_noise_reactivity,
      ring_noise_crowd_gain: state.ring_noise_crowd_gain,
      ring_noise_sat_idle: state.ring_noise_sat_idle,
      ring_noise_activity_bleed: state.ring_noise_activity_bleed,
      presence_floor: state.presence_floor,
      presence_bleed: state.presence_bleed,
      background: state.background,
      display_info: state.display_info
    }

    {canvas, anim_state} =
      Canvas.new(state.display_info.width, state.display_info.height)
      |> state.anim_mod.render(people, ctx, state.anim_state)

    Octopus.App.update_display(canvas, :rgb)
    Octopus.App.update_display(white_channel_canvas(state, ctx), :grayscale)

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
             {"Lava Lamp", :lava_lamp},
             {"Fireflies", :fireflies},
             {"Glowworms", :glowworms},
             {"Ring Noise", :ring_noise},
             {"Presence", :presence}
           ]
         }},
      background:
        {"Background", :select,
         %{
           default: 1,
           options: [{"Deep Dark", :deep_dark}, {"Still Stars", :still_stars}],
           visible_when: {:animation, [:storm]}
         }},
      sensitivity:
        {"Storm Sensitivity", :float,
         %{min: 0.2, max: 3.0, default: 1.0, visible_when: {:animation, [:storm]}}},
      storm_activity_bleed:
        {"Activity Bleed", :float,
         %{
           min: 0.0,
           max: 0.5,
           default: 0.2,
           step: 0.05,
           visible_when: {:animation, [:storm]}
         }},
      storm_reactivity:
        {"Crowd Heat", :float,
         %{
           min: 0.0,
           max: 1.0,
           default: 0.5,
           step: 0.05,
           visible_when: {:animation, [:storm]}
         }},
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
      dots_activity_bleed:
        {"Activity Bleed", :float,
         %{
           min: 0.0,
           max: 0.5,
           default: 0.2,
           step: 0.05,
           visible_when: {:animation, [:dots]}
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
      firefly_reactivity:
        {"Crowd Heat", :float,
         %{
           min: 0.0,
           max: 1.0,
           default: 0.6,
           step: 0.05,
           visible_when: {:animation, [:fireflies]}
         }},
      firefly_speed:
        {"Speed", :float,
         %{
           min: 0.2,
           max: 2.0,
           default: 1.5,
           step: 0.05,
           visible_when: {:animation, [:fireflies]}
         }},
      firefly_count:
        {"Base Count", :int,
         %{
           min: 1,
           max: 40,
           default: 24,
           visible_when: {:animation, [:fireflies]}
         }},
      firefly_glow:
        {"Glow", :float,
         %{
           min: 0.5,
           max: 1.8,
           default: 1.0,
           step: 0.05,
           visible_when: {:animation, [:fireflies]}
         }},
      firefly_flash_rate:
        {"Breath Depth", :float,
         %{
           min: 0.4,
           max: 1.2,
           default: 0.85,
           step: 0.05,
           visible_when: {:animation, [:fireflies]}
         }},
      firefly_palette:
        {"Palette", :select,
         %{
           default: 0,
           options: [
             {"Classic", :classic},
             {"Amber", :amber},
             {"Ghost", :ghost}
           ],
           visible_when: {:animation, [:fireflies]}
         }},
      glowworms_speed:
        {"Speed", :float,
         %{
           min: 0.2,
           max: 5.0,
           default: 1.6,
           step: 0.1,
           visible_when: {:animation, [:glowworms]}
         }},
      glowworms_color_intensity:
        {"Color Intensity", :float,
         %{
           min: 0.0,
           max: 1.0,
           default: 0.55,
           step: 0.05,
           visible_when: {:animation, [:glowworms]}
         }},
      glowworms_max_count:
        {"Max Glowworms", :int,
         %{min: 1, max: 20, default: 13, visible_when: {:animation, [:glowworms]}}},
      glowworms_circling_area:
        {"Circling Area", :int,
         %{min: 1, max: 10, default: 4, visible_when: {:animation, [:glowworms]}}},
      glowworms_stay_chance:
        {"Stay Chance", :float,
         %{
           min: 0.0,
           max: 1.0,
           default: 0.5,
           step: 0.05,
           visible_when: {:animation, [:glowworms]}
         }},
      glowworms_run_away_proximity:
        {"Run Away Proximity", :int,
         %{min: 2, max: 10, default: 5, visible_when: {:animation, [:glowworms]}}},
      glowworms_run_away_count:
        {"Run Away Count", :int,
         %{min: 1, max: 10, default: 3, visible_when: {:animation, [:glowworms]}}},
      glowworms_run_away_duration:
        {"Run Away Duration", :int,
         %{min: 1, max: 10, default: 5, visible_when: {:animation, [:glowworms]}}},
      glowworms_gravity_stay_multiplier:
        {"Gravity Stay Multiplier", :float,
         %{
           min: 1.0,
           max: 10.0,
           default: 3.0,
           step: 0.5,
           visible_when: {:animation, [:glowworms]}
         }},
      glowworms_birth_proximity_duration:
        {"Birth Proximity Duration", :int,
         %{min: 5, max: 60, default: 30, visible_when: {:animation, [:glowworms]}}},
      glowworms_overpopulation_death_duration:
        {"Overpopulation Death Duration", :int,
         %{min: 5, max: 120, default: 45, visible_when: {:animation, [:glowworms]}}},
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
      ring_noise_crowd_mode:
        {"Crowd Mode", :select,
         %{
           default: 0,
           options: [
             {"Off", :off},
             {"Brightness", :brightness},
             {"Saturation", :saturation}
           ],
           visible_when: {:animation, [:ring_noise]}
         }},
      ring_noise_reactivity:
        {"Crowd Heat", :float,
         %{
           min: 0.0,
           max: 1.0,
           default: 0.0,
           step: 0.05,
           visible_when: {:animation, [:ring_noise]}
         }},
      ring_noise_crowd_gain:
        {"Boost", :float,
         %{
           min: 0.2,
           max: 2.0,
           default: 1.0,
           step: 0.05,
           visible_when: {:animation, [:ring_noise]}
         }},
      ring_noise_sat_idle:
        {"Idle Saturation", :float,
         %{
           min: 0.0,
           max: 0.5,
           default: 0.22,
           step: 0.02,
           visible_when: {:animation, [:ring_noise]}
         }},
      ring_noise_activity_bleed:
        {"Activity Bleed", :float,
         %{
           min: 0.0,
           max: 0.7,
           default: 0.3,
           step: 0.05,
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
    spawns already inside. Panel activity scales bolt probability per panel.
    • Storm Sensitivity — scales bolt probability for a given speed (higher = more).
    • Activity Bleed — how much activity spills into adjacent panels for bolt weighting.
    • Crowd Heat — master panel-activity influence on bolt rate (0 = speed only).
    • Background — Deep Dark (black) or Still Stars (starfield + wandering moon
      that cycles new→full→new, plus 1–2 blinking satellites).
    """
  end

  def config_info(%{animation: :breath}) do
    """
    Crowd Breath — wave + local colour.
    Wave shape (level, height, flow) and ring colour come from the shared
    panel-activity service (`Radar.panel_factors/0`): mean activity drives
    density, peak activity drives flow. Colour is per-panel (8 px blocks) with
    light neighbour bleed. People in the 2 m center chill disk have no ring
    column — in Canopy layout they drive the upper half instead.
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
    Y = distance from centre: at the ring / near the panels → top row;
    at the centre → bottom row. Stable colour per track id.
    Panel activity glows on the warm-white (W) channel from the shared
    panel-activity service; RGB carries dots and pulses only.
    Walking speed soft-blinks each dot (cosine fade, faster when moving faster).
    After 3 s without movement, a soft ring pulse expands over ~3–4 panels and fades.
    • Dot Smoothing — low = snappy, high = soft follow (EMA on position).
    • Activity Bleed — how much activity spills into adjacent panels.
    """
  end

  def config_info(%{animation: :lava_lamp}) do
    """
    Lava Lamp — cylindrical metaball blobs driven by crowd heat.
    Brightness and motion follow the shared radar panel-activity service: hot
    zones lift and inflate blobs, speed up convection and warm the palette. Empty
    room = slow cold lamp. Crowd Heat 0 = classic crowd-blind decorative lava.
    • Crowd Heat — master crowd influence (0 = ignore the crowd).
    • Speed — base animation time scale (not frame rate).
    • Warmth — how much the palette cools when the room is empty.
    • Palette — Classic, Magenta, or Slime (hot end of the temperature axis).
    """
  end

  def config_info(%{animation: :fireflies}) do
    """
    Fireflies — soft bioluminescent points drifting over a night field.
    Global crowd heat spawns more fireflies (smooth fade in/out); local heat
    attracts them into swarms over busy panels. Each one glows with a slow breath,
    no discrete blinks.
    • Crowd Heat — master crowd influence (0 = fixed meadow, no sensor needed).
    • Speed — drift and breath time scale.
    • Base Count — fireflies visible with an empty room.
    • Glow — point size.
    • Breath Depth — how strongly each firefly pulses.
    • Palette — Classic, Amber, or Ghost colour pairs.
    """
  end

  def config_info(%{animation: :glowworms}) do
    """
    Glowworms — bright dots with a soft corona and fluttering wings.
    They fly horizontally, clustering together or seeking gravity sources.
    They can meet, birth new glowworms, or scatter if overcrowded.
    • Max Count — population limit.
    • Color Intensity — white to pastel balance.
    • Stay Chance — tendency to stop traveling when meeting.
    • Gravity Stay Multiplier — how much longer they stay at gravity points.
    """
  end

  def config_info(%{animation: :ring_noise}) do
    """
    Ring Noise — seamless cylindrical noise field with palette colours and
    counter-rotating brightness waves. Optional crowd modes use the shared
    radar panel-activity service.
    • Crowd Mode — Off (deco), Brightness (hot panels glow), or Saturation
      (idle desaturated, crowd restores colour).
    • Crowd Heat — master crowd influence (0 = ignore the crowd).
    • Noise Speed — how fast the noise field evolves.
    • Palette — Lava, Ocean, or Aurora colour stops.
    """
  end

  def config_info(%{animation: :presence}) do
    """
    Presence — each panel glows fully in a fixed random colour.
    Brightness follows the shared radar panel-activity service (crowd
    proximity, count, walking speed), with visual neighbour bleed and base
    glow applied here. Activity also glows on the warm-white (W) channel.
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
      storm_activity_bleed: state.storm_activity_bleed,
      storm_reactivity: state.storm_reactivity,
      breath_liveliness: state.breath_liveliness,
      breath_palette: state.breath_palette,
      breath_hue_shift: state.breath_hue_shift,
      breath_layout: state.breath_layout,
      dots_smoothing: state.dots_smoothing,
      dots_activity_bleed: state.dots_activity_bleed,
      lava_blob_count: state.lava_blob_count,
      lava_speed: state.lava_speed,
      lava_size_mul: state.lava_size_mul,
      lava_thresh: state.lava_thresh,
      lava_palette: state.lava_palette,
      lava_reactivity: state.lava_reactivity,
      lava_warmth: state.lava_warmth,
      firefly_count: state.firefly_count,
      firefly_speed: state.firefly_speed,
      firefly_reactivity: state.firefly_reactivity,
      firefly_glow: state.firefly_glow,
      firefly_flash_rate: state.firefly_flash_rate,
      firefly_palette: state.firefly_palette,
      glowworms_speed: state.glowworms_speed,
      glowworms_color_intensity: state.glowworms_color_intensity,
      glowworms_max_count: state.glowworms_max_count,
      glowworms_circling_area: state.glowworms_circling_area,
      glowworms_stay_chance: state.glowworms_stay_chance,
      glowworms_run_away_proximity: state.glowworms_run_away_proximity,
      glowworms_run_away_count: state.glowworms_run_away_count,
      glowworms_run_away_duration: state.glowworms_run_away_duration,
      glowworms_gravity_stay_multiplier: state.glowworms_gravity_stay_multiplier,
      glowworms_birth_proximity_duration: state.glowworms_birth_proximity_duration,
      glowworms_overpopulation_death_duration: state.glowworms_overpopulation_death_duration,
      ring_noise_speed: state.ring_noise_speed,
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
         storm_activity_bleed:
           Map.get(config, :storm_activity_bleed, state.storm_activity_bleed),
         storm_reactivity: Map.get(config, :storm_reactivity, state.storm_reactivity),
         breath_liveliness: Map.get(config, :breath_liveliness, state.breath_liveliness),
         breath_palette: Map.get(config, :breath_palette, state.breath_palette),
         breath_hue_shift: Map.get(config, :breath_hue_shift, state.breath_hue_shift),
         breath_layout: Map.get(config, :breath_layout, state.breath_layout),
         dots_smoothing: Map.get(config, :dots_smoothing, state.dots_smoothing),
         dots_activity_bleed: Map.get(config, :dots_activity_bleed, state.dots_activity_bleed),
         lava_blob_count: Map.get(config, :lava_blob_count, state.lava_blob_count),
         lava_speed: Map.get(config, :lava_speed, state.lava_speed),
         lava_size_mul: Map.get(config, :lava_size_mul, state.lava_size_mul),
         lava_thresh: Map.get(config, :lava_thresh, state.lava_thresh),
         lava_palette: Map.get(config, :lava_palette, state.lava_palette),
         lava_reactivity: Map.get(config, :lava_reactivity, state.lava_reactivity),
         lava_warmth: Map.get(config, :lava_warmth, state.lava_warmth),
         firefly_count: Map.get(config, :firefly_count, state.firefly_count),
         firefly_speed: Map.get(config, :firefly_speed, state.firefly_speed),
         firefly_reactivity: Map.get(config, :firefly_reactivity, state.firefly_reactivity),
         firefly_glow: Map.get(config, :firefly_glow, state.firefly_glow),
         firefly_flash_rate: Map.get(config, :firefly_flash_rate, state.firefly_flash_rate),
         firefly_palette: Map.get(config, :firefly_palette, state.firefly_palette),
         glowworms_speed: Map.get(config, :glowworms_speed, state.glowworms_speed),
         glowworms_color_intensity:
           Map.get(config, :glowworms_color_intensity, state.glowworms_color_intensity),
         glowworms_max_count: Map.get(config, :glowworms_max_count, state.glowworms_max_count),
         glowworms_circling_area:
           Map.get(config, :glowworms_circling_area, state.glowworms_circling_area),
         glowworms_stay_chance: Map.get(config, :glowworms_stay_chance, state.glowworms_stay_chance),
         glowworms_run_away_proximity:
           Map.get(config, :glowworms_run_away_proximity, state.glowworms_run_away_proximity),
         glowworms_run_away_count:
           Map.get(config, :glowworms_run_away_count, state.glowworms_run_away_count),
         glowworms_run_away_duration:
           Map.get(config, :glowworms_run_away_duration, state.glowworms_run_away_duration),
         glowworms_gravity_stay_multiplier:
           Map.get(config, :glowworms_gravity_stay_multiplier, state.glowworms_gravity_stay_multiplier),
         glowworms_birth_proximity_duration:
           Map.get(config, :glowworms_birth_proximity_duration, state.glowworms_birth_proximity_duration),
         glowworms_overpopulation_death_duration:
           Map.get(config, :glowworms_overpopulation_death_duration, state.glowworms_overpopulation_death_duration),
         ring_noise_speed: Map.get(config, :ring_noise_speed, state.ring_noise_speed),
         ring_noise_pulse_period:
           Map.get(config, :ring_noise_pulse_period, state.ring_noise_pulse_period),
         ring_noise_pulse_amount:
           Map.get(config, :ring_noise_pulse_amount, state.ring_noise_pulse_amount),
         ring_noise_counter_wave:
           Map.get(config, :ring_noise_counter_wave, state.ring_noise_counter_wave),
         ring_noise_palette: Map.get(config, :ring_noise_palette, state.ring_noise_palette),
         ring_noise_crowd_mode:
           Map.get(config, :ring_noise_crowd_mode, state.ring_noise_crowd_mode) |> coerce_atom(:off),
         ring_noise_reactivity:
           Map.get(config, :ring_noise_reactivity, state.ring_noise_reactivity),
         ring_noise_crowd_gain: Map.get(config, :ring_noise_crowd_gain, state.ring_noise_crowd_gain),
         ring_noise_sat_idle: Map.get(config, :ring_noise_sat_idle, state.ring_noise_sat_idle),
         ring_noise_activity_bleed:
           Map.get(config, :ring_noise_activity_bleed, state.ring_noise_activity_bleed),
         presence_floor: Map.get(config, :presence_floor, state.presence_floor),
         presence_bleed: Map.get(config, :presence_bleed, state.presence_bleed)
     }}
  end

  defp fetch_people(state, now) do
    registry_people =
      Map.get(state, :track_registry, %{})
      |> active_people(now, @track_stale_ms)
      |> TrackMerge.merge()

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
  defp coerce_config_value(:firefly_palette, value), do: coerce_atom(value, :classic)
  defp coerce_config_value(:ring_noise_palette, value), do: coerce_atom(value, :lava)
  defp coerce_config_value(:ring_noise_crowd_mode, value), do: coerce_atom(value, :off)
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

  defp white_channel_canvas(%{animation: :dots, display_info: info}, ctx) do
    Animations.Dots.activity_canvas(info, Map.get(ctx, :dots_activity_bleed, 0.2))
  end

  defp white_channel_canvas(%{animation: :presence, display_info: info}, ctx) do
    Animations.PresencePanels.activity_canvas(info, Map.get(ctx, :presence_bleed, 0.35))
  end

  defp white_channel_canvas(%{display_info: info}, _ctx) do
    Canvas.new(info.width, info.height, :grayscale)
  end
end
