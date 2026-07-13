defmodule Octopus.Apps.PixelFun3D do
  use Octopus.App, category: :interactive
  use Octopus.Params, prefix: :pixelfun3d

  require Logger

  alias Octopus.Canvas
  alias Octopus.Events.Event.Audio, as: AudioEvent
  alias Octopus.Events.Event.Input, as: InputEvent
  alias Octopus.Events.Event.Proximity, as: ProximityEvent
  alias Octopus.AppSupervisor
  alias Octopus.Apps.PixelFun.Program
  alias Octopus.Apps.PixelFun3D.Zoom
  alias Octopus.Installation
  alias Octopus.Sphere
  alias Octopus.Wander

  @app_mode_presets "Elixir.Octopus.AppModePresets"

  @auto_channels [:trans, :rot, :zoom, :sway, :sat]

  @rot_sweep_easings [:sine_in_out, :smoothstep, :cubic_in_out]

  @auto_defaults %{
    trans_auto: false,
    trans_auto_range_x: 80.0,
    trans_auto_range_y: 3.0,
    trans_auto_interval: 80.0,
    rot_auto: false,
    rot_auto_range: 60.0,
    rot_auto_interval: 60.0,
    zoom_auto: false,
    zoom_auto_range: 1.05,
    zoom_auto_interval: 30.0,
    sway_auto: false,
    sway_auto_range: 2.0,
    sway_auto_interval: 30.0,
    sat_auto: false,
    sat_auto_min: 20.0,
    sat_auto_max: 100.0,
    sat_auto_interval: 30.0
  }

  @channel_bounds %{
    # trans_x is now a horizontal position offset (px, pan) up to ~half the ring;
    # yaw wraps so this only bounds the wander target range.
    trans_x: {-156.0, 156.0},
    trans_y: {-4.0, 4.0},
    rot: {-180.0, 180.0},
    sway: {0.0, 4.0},
    sat: {0.0, 100.0}
  }

  @zoom_factor_min 0.7
  @zoom_factor_max 11.0

  @channel_base_key %{
    rot: :roll_rate,
    zoom: :zoom_base,
    sway: :tilt_scale,
    sat: :saturation_percent
  }

  @default_scene %{
    color_mode: :random,
    saturation_percent: 70,
    brightness_percent: 100,
    color_interval: 5.0,
    palette_auto: true,
    orbit_rate: 0.0,
    roll_rate: 0.0,
    roll_pivot: 0,
    tilt_scale: 0.0,
    tilt_speed: 0.5,
    tilt_mode: :wobble,
    elev_base: 0.0,
    zoom_base: 1.0,
    zoom_pivot: 0,
    pattern_speed: 1.0,
    time_direction: :forward,
    pixel_fun_units: 2
  }
  |> Map.merge(@auto_defaults)

  @tilt_defaults %{tilt_scale: 0.0, tilt_speed: 0.5, tilt_mode: :wobble}

  @removed_zoom_keys [:zoom_rate, :zoom_pulse, :zoom_pulse_speed]
  @removed_elev_keys [:elev_amp, :elev_speed]
  @removed_tx_ty_keys [
    :tx_auto,
    :tx_auto_range,
    :tx_auto_tempo,
    :ty_auto,
    :ty_auto_range,
    :ty_auto_tempo
  ]
  @removed_tempo_keys [:rot_auto_tempo, :zoom_auto_tempo, :sway_auto_tempo, :trans_auto_tempo]

  @builtin_scene_keys ([
                        :color_mode,
                        :saturation_percent,
                        :brightness_percent,
                        :color_interval,
                        :palette_auto,
                        :orbit_rate,
                        :roll_rate,
                        :roll_pivot,
                        :tilt_scale,
                        :tilt_speed,
                        :tilt_mode,
                        :elev_base,
                        :zoom_base,
                        :zoom_pivot,
                        :pattern_speed,
                        :time_direction
                      ] ++ Map.keys(@auto_defaults))
                      |> Enum.uniq()

  @sphere_scene_keys ([
                       :brightness_percent,
                       :orbit_rate,
                       :roll_rate,
                       :roll_pivot,
                       :tilt_scale,
                       :tilt_speed,
                       :tilt_mode,
                       :elev_base,
                       :zoom_base,
                       :zoom_pivot,
                       :pattern_speed
                     ] ++ Map.keys(@auto_defaults))
                     |> Enum.uniq()

  @builtin_defs [
    %{
      slug: "classic_ripple",
      name: "Classic ripple",
      formula: "sin(0.4*t-hypot(x,y))",
      accent_color: "#E74C3C"
    },
    %{
      slug: "cross_waves",
      name: "Cross waves",
      formula: "sin(x*0.7+t*0.4)*cos(y*0.7+t*0.26)",
      accent_color: "#3498DB"
    },
    %{
      slug: "xy_interference",
      name: "XY interference",
      formula: "sin(x*y*0.08)*cos(t*0.4)",
      accent_color: "#9B59B6"
    },
    %{
      slug: "nested_sincos",
      name: "Nested sin/cos",
      formula:
        "sin(x*0.4+sin(y*0.3+t*0.4)*3+t*0.4)*cos(y*0.4+cos(x*0.3+t*0.4)*3+t*0.4)",
      accent_color: "#1ABC9C"
    },
    %{
      slug: "layered_waves",
      name: "Layered waves",
      formula: "sin(x*0.5+t*0.4)*cos(y*0.5+t*0.4)+sin((x+y)*0.35+t*0.6)*0.5",
      accent_color: "#F39C12"
    },
    %{
      slug: "ripple_rings",
      name: "Ripple rings",
      formula: "sin(hypot(x,y)*5-t*0.4)*sin(hypot(x+3,y+3)*5+t*0.27)",
      accent_color: "#E91E63"
    },
    %{
      slug: "organic_swirl",
      name: "Organic swirl",
      formula: "sin(x*y*0.06+sin(t*0.06)*x*0.2-t*0.12)*cos(hypot(x,y)*2+t*0.06)",
      accent_color: "#2ECC71",
      saturation_percent: 50
    },
    %{
      slug: "swaytest",
      name: "Swaytest",
      formula: "tanh(y*4)",
      accent_color: "#FF7043"
    },
    %{
      slug: "kreiswelle",
      name: "Kreiswelle",
      formula: "sin(x*PI*6/156-t*0.4)*cos(y*0.7-t*0.26)",
      accent_color: "#E74C3C"
    },
    %{
      slug: "chaser",
      name: "Chaser",
      formula: "pow(sin(x*PI/156-t*0.4),7)",
      accent_color: "#3498DB"
    },
    %{
      slug: "doppelhelix",
      name: "Doppelhelix",
      formula: "sin(x*PI*3/156-t*0.4+y*0.4)*sin(x*PI*3/156+t*0.27-y*0.4)",
      accent_color: "#9B59B6"
    },
    %{
      slug: "nordlicht",
      name: "Nordlicht",
      formula: "sin(y*0.6+sin(x*PI*5/156+t*0.4)*3)*(0.6+0.4*sin(x*PI*2/156-t*0.3))",
      accent_color: "#1ABC9C"
    },
    %{
      slug: "wolkenzug",
      name: "Wolkenzug",
      formula:
        "sin(x*PI*3/156+t*0.2)*0.5+sin(x*PI*7/156-t*0.13+y*0.4)*0.3+sin(x*PI*11/156+t*0.31+y*0.8)*0.25",
      accent_color: "#F39C12"
    },
    %{
      slug: "seegras",
      name: "Seegras",
      formula: "sin(x*PI*30/156+sin(t*0.4+y*0.6)*(3.5-y)*0.35)",
      accent_color: "#E91E63"
    },
    %{
      slug: "quallenpuls",
      name: "Quallen-Puls",
      formula:
        "exp(-hypot(sin((x+9)*PI/312)*14,y)*0.1)*sin(hypot(sin((x+9)*PI/312)*14,y)*1.5-t*0.4)",
      accent_color: "#2ECC71"
    },
    %{
      slug: "weiche_blobs",
      name: "Weiche Blobs",
      formula: "sin(x*PI*6/156-t*0.4)*sin(y*0.75+sin(x*PI*2/156+t*0.23)*1.5)",
      accent_color: "#FF7043"
    },
    %{
      slug: "leuchtplankton",
      name: "Leuchtplankton",
      formula: "pow(sin(i*13.7+t*0.24)*sin(i*5.3-t*0.16),5)",
      accent_color: "#E74C3C"
    },
    %{
      slug: "wasserwaage",
      name: "Wasserwaage",
      formula: "tanh(y*1.8)",
      accent_color: "#3498DB",
      tilt_scale: 2.5,
      tilt_speed: 0.4,
      tilt_mode: :wobble
    },
    %{
      slug: "sternenhimmel",
      name: "Sternenhimmel",
      formula: "pow(sin(i*13.7+t*0.24)*sin(i*5.3-t*0.16),5)",
      accent_color: "#9B59B6",
      orbit_rate: 2.0
    },
    %{
      slug: "nebeldrift",
      name: "Nebeldrift",
      formula: "noise(nx*2,ny*2,nz*2+t*0.08)",
      accent_color: "#1ABC9C",
      color_mode: :random,
      trans_auto: true,
      trans_auto_range_x: 80.0,
      trans_auto_range_y: 3.0,
      trans_auto_interval: 80
    },
    %{
      slug: "facettenstrudel",
      name: "Facetten-Strudel",
      formula: "sin(nx*8+t*0.4)*sin(ny*8-t*0.27)",
      accent_color: "#F39C12",
      rot_auto: true,
      rot_auto_range: 60,
      rot_auto_interval: 60,
      zoom_auto: true,
      zoom_auto_range: 1.05,
      zoom_auto_interval: 45
    },
    %{
      slug: "marmor",
      name: "Marmor",
      formula: "sin(nx*6+noise(nx*2,ny*2,nz*2)*4+t*0.4)",
      accent_color: "#E91E63",
      color_mode: :white,
      sway_auto: true,
      sway_auto_range: 1.5,
      sway_auto_interval: 35
    },
    %{
      slug: "strudel",
      name: "Strudel",
      formula: "sin(3*atan2(nz,ny)+acos(nx)*6-t*0.4)",
      accent_color: "#2ECC71"
    },
    %{
      slug: "spiralband",
      name: "Spiralband",
      formula: "sin(4*atan2(ny,nx)+nz*30-t*0.4)",
      accent_color: "#FF7043"
    },
    %{
      slug: "globus",
      name: "Globus",
      formula:
        "exp(-pow(nz*5,2))*sin(4*atan2(ny,nx)+nz*20-t*0.4)+exp(-pow((nz-1)*4,2))*sin(3*atan2(ny,nx)+acos(nz)*10+t*0.3)+exp(-pow((nz+1)*4,2))*sin(3*atan2(ny,nx)-acos(-nz)*10-t*0.3)",
      accent_color: "#E74C3C",
      # With roll_pivot 0 the panels near the pivot axis see less parade —
      # the full equator→pole cycle is most dramatic a quarter-ring away.
      roll_rate: 6.0,
      roll_pivot: 0
    },
    %{
      slug: "polarlicht_parade",
      name: "Polar-Parade",
      formula:
        "exp(-pow((nz-1)*3,2))*sin(2*atan2(ny,nx)+acos(nz)*8+t*0.4)+exp(-pow((nz+1)*3,2))*sin(2*atan2(ny,nx)+acos(-nz)*8-t*0.4)",
      accent_color: "#3498DB",
      roll_rate: 4.0,
      roll_pivot: 6
    },
    %{
      slug: "kippende_baender",
      name: "Kippende Bänder",
      formula: "sin(nx*10-t*0.13)",
      accent_color: "#9B59B6",
      rot_auto: true,
      rot_auto_range: 45,
      rot_auto_interval: 60
    },
    %{
      slug: "wabengitter",
      name: "Wabengitter (Debug)",
      # Static two-colour honeycomb defined in direction space (lon=atan2(ny,nx),
      # lat=asin(nz)) via a three-cosine hex lattice. N=48 (even) keeps every lon
      # frequency integer -> seamless around the ring; 41.569 = 48*sqrt(3)/2. Cells
      # are regular hexagons at the equator, so any visible distortion comes from
      # transforms, not the pattern. No `t` -> no motion; palette_auto off freezes
      # the two colours.
      formula:
        "tanh(3*(cos(48*atan2(ny,nx))+cos(24*atan2(ny,nx)+41.569*asin(nz))+cos(24*atan2(ny,nx)-41.569*asin(nz))))",
      accent_color: "#2ECC71",
      color_mode: :random,
      palette_auto: false,
      saturation_percent: 100
    }
  ]

  @fps 30
  @frame_time_ms trunc(1000 / @fps)
  @transform_live_interval_ms 250
  @min_white_level_gap 30
  @min_white_level 32

  defmodule State do
    defstruct [
      :program,
      :source,
      :colors,
      :last_colors,
      :target_colors,
      :lerp_time,
      :orbit_rate,
      :roll_rate,
      :roll_pivot,
      :tilt_scale,
      :tilt_speed,
      :tilt_mode,
      :elev_base,
      :zoom_base,
      :zoom_pivot,
      :pattern_speed,
      :trans_auto,
      :trans_auto_range_x,
      :trans_auto_range_y,
      :trans_auto_interval,
      :rot_auto,
      :rot_auto_range,
      :rot_auto_interval,
      :zoom_auto,
      :zoom_auto_range,
      :zoom_auto_interval,
      :sway_auto,
      :sway_auto_range,
      :sway_auto_interval,
      :sat_auto,
      :sat_auto_min,
      :sat_auto_max,
      :sat_auto_interval,
      :auto_wanderers,
      :rot_auto_pivot,
      :yaw_angle,
      :roll_angle,
      :time_direction,
      :color_mode,
      :saturation_percent,
      :brightness_percent,
      :color_interval,
      :palette_auto,
      # Id of the scene currently rendered on the wall.
      :live_scene_id,
      :audio_input,
      :seconds,
      :buttons,
      :panel_interaction_factors,
      :panel_proximities,
      :speed,
      :display_info,
      :pixel_dirs,
      :time_frozen,
      # Rates captured when freezing; slider deltas against these scrub the
      # frozen image (1 px/s ≙ 1 px, 1 °/s ≙ 1°). nil while unfrozen.
      :frozen_orbit_ref,
      :frozen_roll_ref,
      :show_advanced,
      :formula_seconds,
      :transform_live_last_ms,
      :zoom_octave_n,
      :octave_fade
    ]
  end

  def name(), do: "Pixel Fun 3D"

  def compatible?() do
    Octopus.App.get_installation_info().panel_count >= 1
  end

  def config_schema() do
    %{
      program: {"Formula", :string, %{default: "sin(0.4*t-hypot(x,y))"}},
      color_mode: {"Colors", :atom, %{default: :random}},
      saturation_percent: {"Saturation", :int, %{default: 70, min: 0, max: 100}},
      brightness_percent: {"Brightness", :int, %{default: 100, min: 0, max: 100}},
      sat_auto: {"Saturation Auto", :boolean, %{default: false}},
      sat_auto_min: {"Saturation Min", :float, %{default: 20.0, min: 0, max: 100, step: 1}},
      sat_auto_max: {"Saturation Max", :float, %{default: 100.0, min: 0, max: 100, step: 1}},
      sat_auto_interval: {"Saturation Interval", :float, %{default: 30.0, min: 4, max: 60, step: 1}},
      color_interval: {"Palette tempo (s)", :float, %{default: 5, min: 1, max: 20, step: 0.5}},
      palette_auto: {"Palette Auto", :boolean, %{default: true}},
      orbit_rate: {"Translate X (px/s)", :float, %{default: 0.0, min: -30, max: 30, step: 0.5}},
      elev_base: {"Translate Y (px)", :float, %{default: 0.0, min: -4, max: 4, step: 0.1}},
      roll_rate: {"Rotation (°/s)", :float, %{default: 0.0, min: -180, max: 180, step: 1}},
      zoom_base: {"Zoom (×)", :float, %{default: 1.0, min: 0.7, max: 11, step: 0.05}},
      tilt_scale: {"Sway (px)", :float, %{default: 0.0, min: 0, max: 4, step: 0.1}},
      trans_auto: {"Translate Auto", :boolean, %{default: false}},
      trans_auto_range_x: {"Translate Range X (px)", :float, %{default: 80.0, min: 0, max: 156, step: 2}},
      trans_auto_range_y: {"Translate Range Y (px)", :float, %{default: 3.0, min: 0, max: 4, step: 0.1}},
      trans_auto_interval: {"Translate Interval", :float, %{default: 80.0, min: 4, max: 120, step: 1}},
      rot_auto: {"Rotation Auto", :boolean, %{default: false}},
      rot_auto_range: {"Rotation Sweep (° max)", :float, %{default: 60.0, min: 0, max: 360, step: 5}},
      rot_auto_interval: {"Rotation Interval", :float, %{default: 60.0, min: 4, max: 120, step: 1}},
      zoom_auto: {"Zoom Auto", :boolean, %{default: false}},
      zoom_auto_range: {"Zoom Range (×÷)", :float, %{default: 1.05, min: 1.0, max: 2.0, step: 0.01}},
      zoom_auto_interval: {"Zoom Interval", :float, %{default: 30.0, min: 4, max: 120, step: 1}},
      sway_auto: {"Sway Auto", :boolean, %{default: false}},
      sway_auto_range: {"Sway Range (px)", :float, %{default: 2.0, min: 0, max: 4, step: 0.05}},
      sway_auto_interval: {"Sway Interval", :float, %{default: 30.0, min: 4, max: 120, step: 1}},
      roll_pivot: {"Rotation pivot (panel)", :float, %{default: 0, min: 0, max: 12, step: 1}},
      tilt_speed: {"Sway speed", :float, %{default: 0.5, min: 0, max: 3, step: 0.05}},
      tilt_mode:
        {"Sway mode", :select,
         %{
           default: 0,
           options: [{"Wobble", :wobble}, {"Pendulum", :pendulum}]
         }},
      zoom_pivot: {"Zoom pivot (panel)", :float, %{default: 0, min: 0, max: 12, step: 1}},
      pattern_speed: {"Pattern speed", :float, %{default: 1.0, min: 0.1, max: 3.0, step: 0.05}},
      time_direction:
        {"Time direction", :select,
         %{
           default: 0,
           options: [{"Forward", :forward}, {"Backward", :backward}]
         }},
      bleeding: {"Bleeding", :float, %{default: 50.0, min: 0.0, max: 100.0, step: 1.0}}
    }
  end

  def config_info(_config) do
    """
    Pixel Fun draws a math formula per pixel. Result −1…1 controls brightness; zero renders black. Random dual mode maps positive/negative lobes to two palette colours; Rainbow mode derives hue from pattern coordinates so the full spectrum is visible at once.

    Formula — expression evaluated per pixel. Pick a scene preset tile or type your own; saved scenes persist across restarts. Variables: x, y (chart position on the sphere band), nx/ny/nz (unit view direction — seamless under all transforms), t (time, scaled by global Speed and Pattern speed), i (pixel index), l/m/h (audio bass/mid/high if present), pi, tau. Classic formulas in x remain ring-periodic (azimuth wraps). Builtin formulas are normalized to ~0.4 rad/s; use Pattern speed (Advanced) to deviate per scene.

    Brightness — master output gain (0…100 %, default 100) applied to every colour mode. Saved per scene. The hidden OSC value_percent multiplies on top of this.

    Colors — Random dual maps positive/negative lobes to a complementary hue pair on the colour circle; scrub Palette to pick the hue, Auto advances it (Tempo = seconds per full circle). Rainbow spreads hue across the pattern (moves with orbit/rotation). White dual maps lobes to two brightness levels on the warm W channel of the TM1814 LEDs (no RGB tint); Palette/Auto work the same for brightness pairs.

    Saturation — colour vividness for Random dual and Rainbow (0 = grey, 100 = full; default 70). Auto wanders between Min and Max. White dual ignores saturation.

    Translate X — ring yaw drift in px/s (8 px/s ≈ one panel per second). Auto pans a horizontal position offset instead of scrolling (± Range X px around the current view; the manual rate is paused while Auto is on).

    Translate Y — vertical band shift in px. Shared Translate Auto also pans this (± Range Y px).

    Rotation — roll rate in °/s (30°/s ≈ one full spin per 12 s). Auto instead does eased rotation sweeps: each sweep turns by a random angle (up to ± Sweep°) in a random direction over a random time around a random pivot panel, then a new sweep begins (the manual rate is paused while Auto is on). Rotation pivot (Advanced) only applies when Auto is off; panels near the pivot axis see less parade.

    Zoom — frequency multiplier × (×1 = neutral; higher = finer/denser / farther away; below ×1 = mild magnification toward the zoom pivot). Auto eases very gently in and out around the base (± Range multiplier, e.g. ×1.05), alternating direction across the base. The pattern anchors at the zoom pivot while zooming (phase reference moves toward the pivot as octaves increase). Changing zoom pivot while an octave is active visibly repositions the pattern — acceptable for an Advanced setting. Direction variables nx/ny/nz react only to the bounded Möbius residual (≤ ~×1.41 per octave); use explicit frequency constants in direction-space formulas.

    Sway — small-angle tilt strength in px (Wobble precesses; Pendulum oscillates). Auto wanders strength; Sway speed/mode live in Advanced.

    Auto Interval — seconds between wander targets (shared easing; Translate moves diagonally).

    Time direction — forward (default) or backward. Backward reverses formula animation and manual sphere motion. Auto wanderers and palette Auto ignore time direction (they keep advancing on wall-clock app time).

    Scenes — pick a scene to play it on the wall. Add scenes to the queue to rotate through them at the chosen interval. Some builtins ship with active transforms or autos already on; i-based twinkles (Leuchtplankton / Sternenhimmel) are panel-synchronized by design.
    """
  end

  def get_config(state) do
    scene =
      %{
        program: state.source,
        color_mode: state.color_mode,
        saturation_percent: state.saturation_percent,
        brightness_percent: state.brightness_percent || 100,
        color_interval: state.color_interval,
        palette_auto: state.palette_auto != false,
        orbit_rate: state.orbit_rate,
        roll_rate: state.roll_rate,
        roll_pivot: state.roll_pivot,
        tilt_scale: state.tilt_scale,
        tilt_speed: state.tilt_speed,
        tilt_mode: state.tilt_mode,
        elev_base: state.elev_base,
        zoom_base: state.zoom_base,
        zoom_pivot: state.zoom_pivot,
        pattern_speed: state.pattern_speed || 1.0,
        time_direction: state.time_direction
      }
      |> Map.merge(auto_config_from_state(state))

    Map.merge(scene, %{
      live_scene_id: live_scene_id(state, scene),
      active_preset_id: running_preset_id(state, scene),
      time_frozen: state.time_frozen || false,
      show_advanced: state.show_advanced || false,
      pixel_fun_units: 2
    })
  end

  def list_modes do
    presets().list_modes(__MODULE__)
  end

  def mode_config(mode_id) do
    presets().config_for(__MODULE__, mode_id) || %{}
  end

  def builtin_presets do
    Enum.map(@builtin_defs, fn def ->
      %{
        slug: def.slug,
        name: def.name,
        accent_color: def.accent_color,
        config: builtin_config(def)
      }
    end)
  end

  def legacy_mode_config(slug) do
    case Enum.find(@builtin_defs, &(&1.slug == slug)) do
      nil -> %{}
      def -> builtin_config(def)
    end
  end

  def summary_for_preset(%{config: config}) do
    config = migrate_legacy_config(config)

    channel_bit = fn ch, label, key, unit ->
      if Map.get(config, :"#{ch}_auto", false) do
        case ch do
          :trans ->
            "trans auto±#{format_num(Map.get(config, :trans_auto_range_x, 0))}px/±#{format_num(Map.get(config, :trans_auto_range_y, 0))}px"

          :zoom ->
            "zoom auto×÷#{format_num(Map.get(config, :zoom_auto_range, 1.05))}"

          :rot ->
            "rot sweep±#{format_num(Map.get(config, :rot_auto_range, 60))}°"

          _ ->
            "#{label} auto±#{format_num(Map.get(config, :"#{ch}_auto_range", 0))}#{unit}"
        end
      else
        case ch do
          :zoom ->
            "zoom ×#{format_num(Map.get(config, key, 1.0))}"

          :sway ->
            scale = Map.get(config, key, 0)

            if scale != 0 and scale != 0.0 do
              mode = Map.get(config, :tilt_mode, :wobble)
              "sway #{format_num(scale)}#{unit} #{mode}"
            else
              "sway #{format_num(scale)}#{unit}"
            end

          _ ->
            "#{label} #{format_num(Map.get(config, key, 0))}#{unit}"
        end
      end
    end

    color_mode = Map.get(config, :color_mode, :random)

    palette =
      case color_mode do
        :rainbow ->
          "rainbow"

        :white ->
          if Map.get(config, :palette_auto, true) do
            "white auto #{format_num(config[:color_interval])}s"
          else
            "white static"
          end

        _ ->
          if Map.get(config, :palette_auto, true) do
            "palette auto #{format_num(config[:color_interval])}s"
          else
            "palette static"
          end
      end

    sliders =
      Enum.join(
        [
          if Map.get(config, :trans_auto, false) do
            channel_bit.(:trans, "trans", :orbit_rate, "")
          else
            [
              channel_bit.(:trans, "tx", :orbit_rate, "px/s"),
              "ty #{format_num(Map.get(config, :elev_base, 0))}px"
            ]
            |> Enum.join(" · ")
          end,
          channel_bit.(:rot, "rot", :roll_rate, "°"),
          channel_bit.(:zoom, "zoom", :zoom_base, ""),
          channel_bit.(:sway, "sway", :tilt_scale, "px"),
          if Map.get(config, :sat_auto, false) do
            "sat auto #{format_num(Map.get(config, :sat_auto_min, 20))}–#{format_num(Map.get(config, :sat_auto_max, 100))}%"
          else
            "sat #{format_num(Map.get(config, :saturation_percent, 70))}%"
          end,
          palette
        ],
        " · "
      )

    formula =
      (config[:program] || "")
      |> String.trim()
      |> then(fn f -> if String.length(f) > 28, do: String.slice(f, 0, 25) <> "...", else: f end)

    "#{sliders} · #{formula}"
  end

  defp format_num(n) when is_float(n), do: :erlang.float_to_binary(n, decimals: 1)
  defp format_num(n) when is_integer(n), do: Integer.to_string(n)
  defp format_num(n), do: to_string(n)

  def mode_tweakables(_mode_id) do
    [
      %{
        key: :program,
        label: "Formula",
        type: :formula,
        default: "sin(0.4*t-hypot(x,y))",
        hint: "x y nx ny nz t i · l m h · pi PI tau"
      },
      %{
        key: :color_mode,
        label: "Colors",
        type: :choice,
        default: :random,
        options: [{:random, "Random dual"}, {:rainbow, "Rainbow"}, {:white, "White dual (W channel)"}]
      },
      %{
        key: :brightness_percent,
        label: "Brightness",
        type: :slider,
        min: 0,
        max: 100,
        step: 1,
        default: 100,
        unit: "%"
      },
      %{
        key: :saturation_percent,
        label: "Saturation",
        type: :slider,
        min: 0,
        max: 100,
        step: 1,
        default: 70,
        unit: "%",
        auto_key: :sat_auto,
        disabled_when: {:sat_auto, [true]},
        visible_when: {:color_mode, [:random, :rainbow]}
      },
      %{key: :sat_auto, label: "Auto", type: :toggle, default: false, companion_of: :saturation_percent},
      %{
        key: :sat_auto_min,
        label: "Min",
        type: :slider,
        min: 0.0,
        max: 100.0,
        step: 1.0,
        default: 20.0,
        unit: "%",
        visible_when: {:sat_auto, [true]}
      },
      %{
        key: :sat_auto_max,
        label: "Max",
        type: :slider,
        min: 0.0,
        max: 100.0,
        step: 1.0,
        default: 100.0,
        unit: "%",
        visible_when: {:sat_auto, [true]}
      },
      %{
        key: :sat_auto_interval,
        label: "Interval",
        type: :slider,
        min: 4.0,
        max: 60.0,
        step: 1.0,
        default: 30.0,
        unit: "s",
        visible_when: {:sat_auto, [true]}
      },
      %{
        key: :palette_auto,
        label: "Cycle colors",
        type: :toggle,
        default: true,
        visible_when: {:color_mode, [:random, :white]}
      },
      %{
        key: :color_interval,
        label: "Tempo",
        type: :slider,
        min: 1.0,
        max: 20.0,
        step: 0.5,
        unit: "s",
        default: 5.0,
        visible_when: {:palette_auto, [true]}
      },
      %{
        key: :orbit_rate,
        label: "Translate X",
        type: :slider,
        min: -30.0,
        max: 30.0,
        step: 0.5,
        default: 0.0,
        unit: "px/s",
        auto_key: :trans_auto,
        disabled_when: {:trans_auto, [true]}
      },
      %{key: :trans_auto, label: "Auto", type: :toggle, default: false, companion_of: :orbit_rate},
      %{
        key: :elev_base,
        label: "Translate Y",
        type: :slider,
        min: -4.0,
        max: 4.0,
        step: 0.1,
        default: 0.0,
        unit: "px",
        # Reserve Auto-column width so X/Y tracks align; nest Range/Interval under Y.
        auto_spacer: true,
        disabled_when: {:trans_auto, [true]}
      },
      %{
        key: :trans_auto_range_x,
        label: "Range X",
        type: :slider,
        min: 0.0,
        max: 156.0,
        step: 2.0,
        default: 80.0,
        unit: "px",
        visible_when: {:trans_auto, [true]}
      },
      %{
        key: :trans_auto_range_y,
        label: "Range Y",
        type: :slider,
        min: 0.0,
        max: 4.0,
        step: 0.1,
        default: 3.0,
        unit: "px",
        visible_when: {:trans_auto, [true]}
      },
      %{
        key: :trans_auto_interval,
        label: "Interval",
        type: :slider,
        min: 4.0,
        max: 120.0,
        step: 1.0,
        default: 80.0,
        unit: "s",
        visible_when: {:trans_auto, [true]}
      },
      %{
        key: :roll_rate,
        label: "Rotation",
        type: :slider,
        min: -180.0,
        max: 180.0,
        step: 1.0,
        default: 0.0,
        unit: "°/s",
        auto_key: :rot_auto,
        disabled_when: {:rot_auto, [true]}
      },
      %{key: :rot_auto, label: "Auto", type: :toggle, default: false, companion_of: :roll_rate},
      %{
        key: :rot_auto_range,
        label: "Sweep",
        type: :slider,
        min: 0.0,
        max: 360.0,
        step: 5.0,
        default: 60.0,
        unit: "°",
        visible_when: {:rot_auto, [true]}
      },
      %{
        key: :rot_auto_interval,
        label: "Interval",
        type: :slider,
        min: 4.0,
        max: 120.0,
        step: 1.0,
        default: 60.0,
        unit: "s",
        visible_when: {:rot_auto, [true]}
      },
      %{
        key: :zoom_base,
        label: "Zoom",
        type: :slider,
        min: 0.7,
        max: 11.0,
        step: 0.05,
        default: 1.0,
        unit: "×",
        auto_key: :zoom_auto,
        disabled_when: {:zoom_auto, [true]}
      },
      %{key: :zoom_auto, label: "Auto", type: :toggle, default: false, companion_of: :zoom_base},
      %{
        key: :zoom_auto_range,
        label: "Range",
        type: :slider,
        min: 1.0,
        max: 2.0,
        step: 0.01,
        default: 1.05,
        unit: "×÷",
        visible_when: {:zoom_auto, [true]}
      },
      %{
        key: :zoom_auto_interval,
        label: "Interval",
        type: :slider,
        min: 4.0,
        max: 120.0,
        step: 1.0,
        default: 30.0,
        unit: "s",
        visible_when: {:zoom_auto, [true]}
      },
      %{
        key: :tilt_scale,
        label: "Sway",
        type: :slider,
        min: 0.0,
        max: 4.0,
        step: 0.1,
        default: 0.0,
        unit: "px",
        auto_key: :sway_auto,
        disabled_when: {:sway_auto, [true]}
      },
      %{key: :sway_auto, label: "Auto", type: :toggle, default: false, companion_of: :tilt_scale},
      %{
        key: :sway_auto_range,
        label: "Range",
        type: :slider,
        min: 0.0,
        max: 4.0,
        step: 0.05,
        default: 2.0,
        unit: "px",
        visible_when: {:sway_auto, [true]}
      },
      %{
        key: :sway_auto_interval,
        label: "Interval",
        type: :slider,
        min: 4.0,
        max: 120.0,
        step: 1.0,
        default: 30.0,
        unit: "s",
        visible_when: {:sway_auto, [true]}
      },
      %{
        key: :show_advanced,
        label: "Advanced",
        type: :toggle,
        default: false,
        runtime: true
      },
      %{
        key: :roll_pivot,
        label: "Rotation pivot",
        type: :slider,
        min: 0.0,
        max: 12.0,
        step: 1.0,
        default: 0.0,
        visible_when: {:show_advanced, [true]}
      },
      %{
        key: :tilt_speed,
        label: "Sway speed",
        type: :slider,
        min: 0.0,
        max: 3.0,
        step: 0.05,
        default: 0.5,
        visible_when: {:show_advanced, [true]}
      },
      %{
        key: :tilt_mode,
        label: "Sway mode",
        type: :select,
        options: [{"Wobble", :wobble}, {"Pendulum", :pendulum}],
        default: :wobble,
        visible_when: {:show_advanced, [true]}
      },
      %{
        key: :zoom_pivot,
        label: "Zoom pivot",
        type: :slider,
        min: 0.0,
        max: 12.0,
        step: 1.0,
        default: 0.0,
        visible_when: {:show_advanced, [true]}
      },
      %{
        key: :pattern_speed,
        label: "Pattern speed",
        type: :slider,
        min: 0.1,
        max: 3.0,
        step: 0.05,
        default: 1.0,
        visible_when: {:show_advanced, [true]}
      },
      %{
        key: :time_direction,
        label: "Time direction",
        type: :choice,
        options: [{:forward, "Forward"}, {:backward, "Backward"}],
        default: :forward,
        visible_when: {:show_advanced, [true]}
      },
      %{
        key: :bleeding,
        label: "Bleeding",
        type: :slider,
        min: 0.0,
        max: 100.0,
        step: 1.0,
        unit: "%",
        default: 50.0,
        runtime: true
      },
      %{
        key: :time_frozen,
        label: "Freeze time",
        type: :toggle,
        default: false,
        runtime: true
      }
    ]
  end

  def apply_mode(app_id, mode_id) do
    cast(app_id, {:apply_mode, to_string(mode_id)})
  end

  def app_init(config) do
    Octopus.App.configure_display(layout: :gapped_panels, supports_grayscale: true)
    Octopus.App.subscribe_to_button_events()
    Octopus.Params.Global.subscribe()

    display_info = Octopus.App.get_display_info()
    config = coerce_config(config)

    {:ok, program} = config.program |> Program.parse()

    Process.send_after(self(), :tick, @frame_time_ms)
    color_mode = Map.get(config, :color_mode, :random)
    saturation_percent = Map.get(config, :saturation_percent, 70)
    brightness_percent = coerce_saturation_percent(Map.get(config, :brightness_percent, 100))
    palette = generate_random_palette(color_mode, saturation_percent)
    time_frozen = Map.get(config, :time_frozen, false) |> coerce_boolean()

    palette_auto = Map.get(config, :palette_auto, true) |> coerce_boolean()

    {seconds, micros} = NaiveDateTime.utc_now() |> NaiveDateTime.to_gregorian_seconds()
    seconds = seconds + micros / 1_000_000

    panel_interaction_factors =
      0..(Installation.num_panels() - 1) |> Enum.map(fn i -> {i, 0.0} end) |> Map.new()

    w = Installation.width()
    h = Installation.height()

    pixel_dirs =
      Installation.virtual_pixel_positions_per_panel()
      |> Enum.map(fn panel ->
        Enum.map(panel, fn {x, y} -> {x, y, Sphere.direction(x, y, w, h)} end)
      end)

    state = %State{
      program: program,
      source: config.program,
      colors: palette,
      last_colors: palette,
      target_colors: palette,
      lerp_time: palette_interval_s(config.color_interval),
      color_mode: color_mode,
      saturation_percent: saturation_percent,
      brightness_percent: brightness_percent,
      color_interval: config.color_interval,
      palette_auto: palette_auto,
      orbit_rate: config.orbit_rate,
      roll_rate: config.roll_rate,
      roll_pivot: config.roll_pivot,
      tilt_scale: Map.get(config, :tilt_scale, @tilt_defaults.tilt_scale),
      tilt_speed: Map.get(config, :tilt_speed, @tilt_defaults.tilt_speed),
      tilt_mode: config |> Map.get(:tilt_mode, @tilt_defaults.tilt_mode) |> Octopus.Sway.normalize_mode(),
      elev_base: config.elev_base,
      zoom_base: config.zoom_base,
      zoom_pivot: config.zoom_pivot,
      pattern_speed: Map.get(config, :pattern_speed, 1.0),
      time_direction: config |> Map.get(:time_direction, :forward) |> coerce_time_direction(),
      live_scene_id: scene_presets().id_for_config(config),
      audio_input: %{low: 0.0, mid: 0.0, high: 0.0},
      seconds: seconds,
      formula_seconds: seconds,
      buttons: %{},
      panel_interaction_factors: panel_interaction_factors,
      panel_proximities: Map.new(0..(Installation.num_panels() - 1), fn i -> {i, 0.0} end),
      speed: Octopus.Params.Global.speed(),
      display_info: display_info,
      pixel_dirs: pixel_dirs,
      time_frozen: time_frozen,
      show_advanced: Map.get(config, :show_advanced, false) |> coerce_boolean(),
      yaw_angle: 0.0,
      roll_angle: 0.0,
      zoom_octave_n: 0,
      octave_fade: nil
    }

    state =
      state
      |> put_auto_fields(config)
      |> init_auto_wanderers()

    state = if state.time_frozen, do: capture_frozen_refs(state), else: state

    {:ok, state}
  end

  def handle_config(config, %State{} = state) do
    state = apply_scene_fields(state, config)

    state =
      if Map.has_key?(config, :zoom_base) do
        z = max(state.zoom_base || 1.0, @zoom_factor_min)
        {updates, _committed_n, _fade} = Zoom.advance_octave_state(state, z, state.seconds)
        struct(State, Map.merge(Map.from_struct(state), updates))
      else
        state
      end

    state = push_frame(state)
    broadcast_config(state)
    {:noreply, state}
  end

  defp cast(app_id, message) do
    case AppSupervisor.lookup_app(app_id) do
      {pid, _module} -> GenServer.cast(pid, message)
      _ -> :ok
    end
  end

  def update_program(pid, program) do
    program =
      case Program.parse(program) do
        {:ok, program} -> program
        _ -> 0
      end

    GenServer.cast(pid, {:update_program, program})
  end

  def handle_cast({:update_program, program}, %State{} = state) do
    state = %{state | program: program}
    state = if state.time_frozen, do: push_frame(state), else: state
    {:noreply, state}
  end

  def handle_cast({:apply_mode, scene_id}, %State{} = state) do
    state = apply_scene_by_id(state, scene_id)
    state = %State{state | live_scene_id: scene_id}
    state = if state.time_frozen, do: push_frame(state), else: state
    broadcast_config(state)
    {:noreply, state}
  end

  defp apply_scene_fields(%State{} = state, config) do
    config = coerce_config(config)
    old_state = state
    program_source = Map.get(config, :program, state.source)

    program =
      case Program.parse(program_source) do
        {:ok, program} -> program
        _ -> state.program
      end

    color_interval = Map.get(config, :color_interval, state.color_interval)
    color_mode = Map.get(config, :color_mode, state.color_mode)
    saturation_percent = Map.get(config, :saturation_percent, state.saturation_percent || 70)

    brightness_percent =
      coerce_saturation_percent(
        Map.get(config, :brightness_percent, state.brightness_percent || 100)
      )
    palette_auto =
      Map.get(config, :palette_auto, state.palette_auto != false) |> coerce_boolean()

    old_autos = auto_flags(state)

    state = %State{
      state
      | program: program,
        source: program_source,
        orbit_rate: Map.get(config, :orbit_rate, state.orbit_rate),
        roll_rate: Map.get(config, :roll_rate, state.roll_rate),
        roll_pivot: Map.get(config, :roll_pivot, state.roll_pivot),
        tilt_scale: Map.get(config, :tilt_scale, state.tilt_scale),
        tilt_speed: Map.get(config, :tilt_speed, state.tilt_speed),
        tilt_mode:
          config
          |> Map.get(:tilt_mode, state.tilt_mode)
          |> Octopus.Sway.normalize_mode(),
        elev_base: Map.get(config, :elev_base, state.elev_base),
        zoom_base: Map.get(config, :zoom_base, state.zoom_base),
        zoom_pivot: Map.get(config, :zoom_pivot, state.zoom_pivot),
        pattern_speed: Map.get(config, :pattern_speed, state.pattern_speed || 1.0),
        time_direction:
          config
          |> Map.get(:time_direction, state.time_direction || :forward)
          |> coerce_time_direction(),
        color_mode: color_mode,
        saturation_percent: saturation_percent,
        brightness_percent: brightness_percent,
        color_interval: color_interval,
        palette_auto: palette_auto,
        show_advanced:
          Map.get(config, :show_advanced, state.show_advanced || false) |> coerce_boolean()
    }

    state = state |> put_auto_fields(config) |> sync_auto_wanderers(old_autos)

    state =
      if color_mode in [:random, :white] and palette_needs_refresh?(state, old_state) do
        apply_palette_colors(state)
      else
        state
      end

    apply_time_frozen(state, config)
  end

  # Colours are random now, so only a colour-mode switch forces a fresh pair.
  # Saturation is applied at render time and palette_auto only gates cycling, so
  # neither should re-roll the live pair (that would make dragging Saturation or
  # toggling Auto jump colours).
  defp palette_needs_refresh?(%State{} = state, %State{} = old_state) do
    state.color_mode != old_state.color_mode
  end

  defp palette_auto_on?(%State{} = state), do: state.palette_auto != false

  defp apply_time_frozen(%State{} = state, config) do
    was_frozen = state.time_frozen || false
    new_frozen = Map.get(config, :time_frozen, was_frozen) |> coerce_boolean()

    cond do
      new_frozen and not was_frozen ->
        %State{capture_frozen_refs(state) | time_frozen: true}

      was_frozen and not new_frozen ->
        %State{bake_frozen_scrub(state) | time_frozen: false}

      true ->
        %State{state | time_frozen: new_frozen}
    end
  end

  # Remember the rates at freeze time; slider deltas against these scrub the
  # frozen image without any jump at the freeze moment itself.
  defp capture_frozen_refs(%State{} = state) do
    %State{
      state
      | frozen_orbit_ref: state.orbit_rate || 0.0,
        frozen_roll_ref: state.roll_rate || 0.0
    }
  end

  # Fold the scrub offset into the integrated angles so unfreezing resumes
  # exactly from the on-screen orientation.
  defp bake_frozen_scrub(%State{} = state) do
    alpha = Sphere.alpha(Installation.width())

    {yaw, roll} =
      frozen_scrub_angles(state, state.yaw_angle || 0.0, state.roll_angle || 0.0, alpha)

    %State{state | yaw_angle: yaw, roll_angle: roll, frozen_orbit_ref: nil, frozen_roll_ref: nil}
  end

  @doc false
  def frozen_scrub_angles(%State{time_frozen: true} = state, yaw, roll, alpha) do
    yaw_off = ((state.orbit_rate || 0.0) - (state.frozen_orbit_ref || 0.0)) * alpha
    roll_off = ((state.roll_rate || 0.0) - (state.frozen_roll_ref || 0.0)) * :math.pi() / 180.0
    {yaw + yaw_off, roll + roll_off}
  end

  def frozen_scrub_angles(_state, yaw, roll, _alpha), do: {yaw, roll}

  defp coerce_config(config) when is_map(config) do
    config
    |> migrate_legacy_config()
    |> Map.new(fn
      {:color_mode, value} -> {:color_mode, coerce_color_mode(value)}
      {:saturation_percent, value} -> {:saturation_percent, coerce_saturation_percent(value)}
      {:brightness_percent, value} -> {:brightness_percent, coerce_saturation_percent(value)}
      {:time_direction, value} -> {:time_direction, coerce_time_direction(value)}
      {:time_frozen, value} -> {:time_frozen, coerce_boolean(value)}
      {:palette_auto, value} -> {:palette_auto, coerce_boolean(value)}
      {:sat_auto, value} -> {:sat_auto, coerce_boolean(value)}
      {:sat_auto_min, value} -> {:sat_auto_min, coerce_saturation_percent(value) * 1.0}
      {:sat_auto_max, value} -> {:sat_auto_max, coerce_saturation_percent(value) * 1.0}
      {:tilt_mode, value} -> {:tilt_mode, Octopus.Sway.normalize_mode(value)}
      {key, value} -> {key, value}
    end)
  end

  @doc false
  def migrate_legacy_config(config) when is_map(config) do
    config = normalize_config_keys(config)
    original_keys = MapSet.new(Map.keys(config))
    needs_units? = needs_display_unit_conversion?(config)

    migrated =
      config
      |> maybe_migrate_sway()
      |> maybe_migrate_rotate()
      |> maybe_migrate_translate()
      |> maybe_migrate_zoom()
      |> maybe_migrate_elev_drift()
      |> maybe_migrate_trans_auto()
      |> maybe_migrate_auto_tempos()
      |> maybe_migrate_display_units(needs_units?, original_keys)
      |> normalize_zoom_base()
      |> strip_removed_zoom_keys()
      |> Map.drop(@removed_elev_keys ++ @removed_tx_ty_keys ++ @removed_tempo_keys)

    Map.merge(Map.take(@default_scene, @sphere_scene_keys), migrated)
    |> Map.put(:pixel_fun_units, 2)
    |> Map.drop(@removed_elev_keys ++ @removed_zoom_keys ++ @removed_tx_ty_keys ++ @removed_tempo_keys)
  end

  defp needs_display_unit_conversion?(config) do
    cond do
      Map.get(config, :pixel_fun_units) == 2 ->
        false

      Map.get(config, :legacy_internal_units) == true ->
        true

      true ->
        Enum.any?(
          [
            :tx_auto,
            :ty_auto,
            :tx_auto_range,
            :ty_auto_range,
            :tx_auto_tempo,
            :ty_auto_tempo,
            :rot_auto_tempo,
            :zoom_auto_tempo,
            :sway_auto_tempo,
            :elev_amp,
            :translate_scale,
            :rotate_scale,
            :zoom_scale,
            :zoom_pulse
          ],
          &Map.has_key?(config, &1)
        )
    end
  end

  # Legacy configs stored orbit/roll in rad/s and zoom as log-sigma.
  defp maybe_migrate_display_units(config, false, _keys), do: config

  defp maybe_migrate_display_units(config, true, keys) do
    w = installation_width_for_migration(config)

    config
    |> convert_orbit_to_px_s(w, keys)
    |> convert_roll_to_deg_s(keys)
    |> convert_zoom_to_factor(keys)
    |> convert_trans_range_x(w, keys)
    |> convert_rot_range_to_deg_s(keys)
    |> convert_zoom_range_to_multiplier(keys)
    |> Map.drop([:legacy_internal_units])
  end

  defp normalize_config_keys(config) do
    Map.new(config, fn
      {k, v} when is_atom(k) -> {k, v}
      {k, v} when is_binary(k) -> {String.to_existing_atom(k), v}
    end)
  rescue
    ArgumentError ->
      Map.new(config, fn
        {k, v} when is_atom(k) -> {k, v}
        {k, v} when is_binary(k) -> {String.to_atom(k), v}
      end)
  end

  defp maybe_migrate_sway(config) do
    if Map.has_key?(config, :sway_scale) and not Map.has_key?(config, :tilt_scale) do
      config
      |> Map.put(:tilt_scale, Map.get(config, :sway_scale, 0.0))
      |> Map.put(:tilt_speed, Map.get(config, :sway_speed, @tilt_defaults.tilt_speed))
      |> Map.put(:tilt_mode, Map.get(config, :sway_mode, @tilt_defaults.tilt_mode))
    else
      config
    end
  end

  defp maybe_migrate_rotate(config) do
    if Map.has_key?(config, :rotate_scale) and not Map.has_key?(config, :roll_rate) do
      Map.put(config, :roll_rate, Map.get(config, :rotate_scale, 0.0))
    else
      config
    end
  end

  defp maybe_migrate_translate(config) do
    # Legacy translate_scale was vertical drift amplitude → elev_amp.
    if Map.has_key?(config, :translate_scale) and not Map.has_key?(config, :elev_amp) and
         not Map.has_key?(config, :ty_auto) and not Map.has_key?(config, :trans_auto) do
      config
      |> Map.put(:elev_amp, Map.get(config, :translate_scale, 0.0))
      |> Map.put_new(:elev_speed, 0.05)
    else
      config
    end
  end

  defp maybe_migrate_zoom(config) do
    # Legacy zoom_scale mapped to zoom_pulse; pulse is removed — drop after log in strip.
    if Map.has_key?(config, :zoom_scale) and not Map.has_key?(config, :zoom_pulse) and
         not Map.has_key?(config, :zoom_base) do
      z = Map.get(config, :zoom_scale, 1.0)
      Map.put(config, :zoom_pulse, z * 0.1)
    else
      config
    end
  end

  defp maybe_migrate_elev_drift(config) do
    amp = Map.get(config, :elev_amp, 0.0) || 0.0

    if is_number(amp) and amp > 0 and not Map.get(config, :ty_auto, false) and
         not Map.get(config, :trans_auto, false) do
      config
      |> Map.put(:ty_auto, true)
      |> Map.put(:ty_auto_range, amp * 1.0)
      |> Map.put(:ty_auto_tempo, (Map.get(config, :elev_speed, 0.2) || 0.2) * 1.0)
    else
      config
    end
  end

  defp maybe_migrate_trans_auto(config) do
    has_legacy? =
      Map.has_key?(config, :tx_auto) or Map.has_key?(config, :ty_auto) or
        Map.has_key?(config, :tx_auto_range) or Map.has_key?(config, :ty_auto_range)

    if has_legacy? and not Map.has_key?(config, :trans_auto) do
      tx = Map.get(config, :tx_auto, false) in [true, "true", 1]
      ty = Map.get(config, :ty_auto, false) in [true, "true", 1]

      config
      |> Map.put(:trans_auto, tx or ty)
      |> Map.put(
        :trans_auto_range_x,
        Map.get(config, :tx_auto_range, @auto_defaults.trans_auto_range_x) * 1.0
      )
      |> Map.put(
        :trans_auto_range_y,
        Map.get(config, :ty_auto_range, @auto_defaults.trans_auto_range_y) * 1.0
      )
      |> maybe_put_tempo_as_interval(:trans_auto_interval, [
        Map.get(config, :tx_auto_tempo),
        Map.get(config, :ty_auto_tempo)
      ])
    else
      config
    end
  end

  defp maybe_migrate_auto_tempos(config) do
    Enum.reduce([:rot, :zoom, :sway], config, fn ch, acc ->
      tempo_key = :"#{ch}_auto_tempo"
      interval_key = :"#{ch}_auto_interval"

      if Map.has_key?(acc, tempo_key) and not Map.has_key?(acc, interval_key) do
        Map.put(acc, interval_key, tempo_to_interval(Map.get(acc, tempo_key)))
      else
        acc
      end
    end)
  end

  defp maybe_put_tempo_as_interval(config, interval_key, tempos) do
    if Map.has_key?(config, interval_key) do
      config
    else
      tempo =
        tempos
        |> Enum.filter(&is_number/1)
        |> case do
          [] -> 0.25
          list -> Enum.max(list)
        end

      Map.put(config, interval_key, tempo_to_interval(tempo))
    end
  end

  defp tempo_to_interval(tempo) when is_number(tempo) do
    (12.0 / max(tempo * 1.0, 0.2)) |> max(4.0) |> min(60.0)
  end

  defp tempo_to_interval(_), do: 30.0

  defp installation_width_for_migration(_config) do
    # Prefer live installation; fall back to Nation2026 ring width (12*(8+18)=312).
    try do
      Installation.width()
    rescue
      _ -> 312
    end
  end

  defp convert_orbit_to_px_s(config, w, keys) do
    if MapSet.member?(keys, :orbit_rate) do
      case Map.get(config, :orbit_rate) do
        v when is_number(v) ->
          px = v * w / (:math.pi() * 2)
          {clamped, _} = clamp_log(px, -30.0, 30.0, :orbit_rate)
          Map.put(config, :orbit_rate, clamped)

        _ ->
          config
      end
    else
      config
    end
  end

  defp convert_roll_to_deg_s(config, keys) do
    if MapSet.member?(keys, :roll_rate) or MapSet.member?(keys, :rotate_scale) do
      case Map.get(config, :roll_rate) do
        v when is_number(v) ->
          deg = v * 180.0 / :math.pi()
          {clamped, _} = clamp_log(deg, -180.0, 180.0, :roll_rate)
          Map.put(config, :roll_rate, clamped)

        _ ->
          config
      end
    else
      config
    end
  end

  defp convert_zoom_to_factor(config, keys) do
    if MapSet.member?(keys, :zoom_base) do
      case Map.get(config, :zoom_base) do
        v when is_number(v) ->
          Map.put(config, :zoom_base, :math.exp(v))

        _ ->
          config
      end
    else
      config
    end
  end

  defp convert_trans_range_x(config, w, keys) do
    if MapSet.member?(keys, :tx_auto_range) or MapSet.member?(keys, :trans_auto_range_x) do
      case Map.get(config, :trans_auto_range_x) do
        v when is_number(v) ->
          px = v * w / (:math.pi() * 2)
          {clamped, _} = clamp_log(px, 0.0, 15.0, :trans_auto_range_x)
          Map.put(config, :trans_auto_range_x, clamped)

        _ ->
          config
      end
    else
      config
    end
  end

  defp convert_rot_range_to_deg_s(config, keys) do
    if MapSet.member?(keys, :rot_auto_range) do
      case Map.get(config, :rot_auto_range) do
        v when is_number(v) ->
          deg = v * 180.0 / :math.pi()
          {clamped, _} = clamp_log(deg, 0.0, 360.0, :rot_auto_range)
          Map.put(config, :rot_auto_range, clamped)

        _ ->
          config
      end
    else
      config
    end
  end

  defp convert_zoom_range_to_multiplier(config, keys) do
    if MapSet.member?(keys, :zoom_auto_range) do
      case Map.get(config, :zoom_auto_range) do
        v when is_number(v) ->
          mult = :math.exp(abs(v))
          {clamped, _} = clamp_log(mult, 1.0, 3.0, :zoom_auto_range)
          Map.put(config, :zoom_auto_range, clamped)

        _ ->
          config
      end
    else
      config
    end
  end

  defp clamp_log(v, lo, hi, key) do
    clamped = v |> max(lo) |> min(hi)

    if clamped != v do
      Logger.info("PixelFun3D: clamped #{key} #{inspect(v)} → #{inspect(clamped)}")
      {clamped, true}
    else
      {clamped, false}
    end
  end

  defp normalize_zoom_base(config) do
    case Map.get(config, :zoom_base) do
      v when is_number(v) and v < @zoom_factor_min ->
        Logger.warning("PixelFun3D: legacy zoom_base #{inspect(v)} clamped to #{@zoom_factor_min}")
        Map.put(config, :zoom_base, @zoom_factor_min * 1.0)

      v when is_number(v) ->
        Map.put(config, :zoom_base, v |> max(@zoom_factor_min) |> min(@zoom_factor_max))

      _ ->
        config
    end
  end

  defp strip_removed_zoom_keys(config) do
    dropped =
      @removed_zoom_keys
      |> Enum.filter(fn k ->
        v = Map.get(config, k)
        is_number(v) and v != 0
      end)

    if dropped != [] do
      Logger.info(
        "PixelFun3D: dropping legacy zoom motion #{inspect(Map.take(config, dropped))} from preset config"
      )
    end

    Map.drop(config, @removed_zoom_keys)
  end

  defp coerce_color_mode(value) when is_atom(value), do: value

  defp coerce_color_mode(value) when is_binary(value) do
    case value do
      "random" -> :random
      "rainbow" -> :rainbow
      "white" -> :white
      _ -> :random
    end
  end

  defp coerce_color_mode(_), do: :random

  defp coerce_saturation_percent(value) when is_integer(value), do: value |> max(0) |> min(100)

  defp coerce_saturation_percent(value) when is_float(value),
    do: value |> trunc() |> coerce_saturation_percent()

  defp coerce_saturation_percent(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, _} -> coerce_saturation_percent(n)
      :error -> 70
    end
  end

  defp coerce_saturation_percent(_), do: 70

  defp coerce_time_direction(value) when value in [:forward, :backward], do: value

  defp coerce_time_direction("forward"), do: :forward
  defp coerce_time_direction("backward"), do: :backward
  defp coerce_time_direction(_), do: :forward

  defp coerce_boolean(value) when value in [true, false], do: value
  defp coerce_boolean("true"), do: true
  defp coerce_boolean("false"), do: false
  defp coerce_boolean(1), do: true
  defp coerce_boolean(0), do: false
  defp coerce_boolean(_), do: false

  defp time_sign(:backward), do: -1
  defp time_sign(_), do: 1

  defp apply_scene_by_id(%State{} = state, scene_id) do
    case config_for_scene_id(scene_id) do
      nil ->
        state

      config ->
        state
        |> apply_scene_fields(config)
        |> reset_orientation_from_scene(config)
    end
  end

  # Builtin playback prefers `@builtin_defs` over insert-only DB rows so recipe
  # transforms (wasserwaage sway, etc.) stay in sync with code.
  defp config_for_scene_id(scene_id) when is_binary(scene_id) do
    slug =
      cond do
        String.starts_with?(scene_id, "builtin:") ->
          String.replace_prefix(scene_id, "builtin:", "")

        String.starts_with?(scene_id, "pixelfun3d:") ->
          String.replace_prefix(scene_id, "pixelfun3d:", "")

        true ->
          nil
      end

    code =
      if is_binary(slug) do
        case legacy_mode_config(slug) do
          %{} = c when map_size(c) > 0 -> migrate_legacy_config(c)
          _ -> nil
        end
      end

    cond do
      code != nil and (String.starts_with?(scene_id, "builtin:") or builtin_slug?(slug)) ->
        code

      true ->
        mod = scene_presets()

        case apply(mod, :get, [scene_id]) do
          nil -> nil
          preset -> apply(mod, :to_config, [preset])
        end
    end
  end

  defp builtin_slug?(slug) when is_binary(slug) do
    Enum.any?(@builtin_defs, &(&1.slug == slug))
  end

  defp builtin_slug?(_), do: false

  # Scene load must win over auto-off handover and leftover integrated angles,
  # otherwise a prior sway/orbit auto leaves a tilted "horizon" on neutral presets.
  defp reset_orientation_from_scene(%State{} = state, config) do
    state = %State{
      state
      | orbit_rate: Map.get(config, :orbit_rate, 0.0),
        elev_base: Map.get(config, :elev_base, 0.0),
        roll_rate: Map.get(config, :roll_rate, 0.0),
        zoom_base: Map.get(config, :zoom_base, 1.0),
        tilt_scale: Map.get(config, :tilt_scale, 0.0),
        tilt_speed: Map.get(config, :tilt_speed, @tilt_defaults.tilt_speed),
        tilt_mode:
          config
          |> Map.get(:tilt_mode, @tilt_defaults.tilt_mode)
          |> Octopus.Sway.normalize_mode(),
        yaw_angle: 0.0,
        roll_angle: 0.0,
        rot_auto_pivot: nil
    }

    # New scene, new rates — rebase the frozen scrub so it starts at zero.
    if state.time_frozen, do: capture_frozen_refs(state), else: state
  end

  defp broadcast_config(%State{} = state) do
    case AppSupervisor.lookup_app_id(self()) do
      nil ->
        :ok

      app_id ->
        Phoenix.PubSub.broadcast(
          Octopus.PubSub,
          "apps",
          {:apps, {:config_updated, app_id, get_config(state)}}
        )
    end
  end

  # Id of the scene currently on the wall. Prefers the explicitly tracked id
  # (set whenever a scene is loaded) and falls back to an exact scene match.
  defp live_scene_id(%State{live_scene_id: id}, _scene) when is_binary(id), do: id
  defp live_scene_id(_state, scene), do: scene_presets().id_for_config(scene)

  defp running_preset_id(%State{live_scene_id: id}, _scene) when is_binary(id), do: id
  defp running_preset_id(_state, scene), do: scene_presets().id_for_config(scene)

  defp scene_presets, do: String.to_existing_atom("Elixir.Octopus.Apps.PixelFun3D.ScenePresets")

  defp presets, do: String.to_existing_atom(@app_mode_presets)

  defp builtin_config(def) do
    @default_scene
    |> Map.put(:program, def.formula)
    |> Map.merge(Map.take(def, @builtin_scene_keys))
  end

  def handle_info({:param_updated, :speed, new_value}, %State{} = state) do
    {:noreply, %{state | speed: new_value}}
  end

  def handle_info({:param_updated, _key, _value}, %State{} = state) do
    {:noreply, state}
  end

  def handle_info(:tick, %State{} = state) do
    tick_start = System.monotonic_time(:millisecond)

    state =
      if state.time_frozen do
        # Freeze means a static image: pattern time, palette, autos AND the
        # rate-driven yaw/roll drift all halt. Translate X / Rotation are
        # velocities — integrating them while frozen would keep the image
        # moving whenever a scene has nonzero drift. Positional controls
        # (Translate Y, Zoom, pivots, palette) still act on the frozen frame
        # via handle_config/push_frame.
        state
      else
        state
        |> advance_palette_colors()
        |> advance_tick_state()
        |> maybe_broadcast_transform_live(tick_start)
      end

    state = push_frame(state)
    elapsed = System.monotonic_time(:millisecond) - tick_start
    Process.send_after(self(), :tick, max(@frame_time_ms - elapsed, 1))
    {:noreply, state}
  end

  defp maybe_broadcast_transform_live(%State{} = state, now_ms) do
    last_ms = state.transform_live_last_ms || 0

    if any_auto?(state) and now_ms - last_ms >= @transform_live_interval_ms do
      case AppSupervisor.lookup_app_id(self()) do
        nil ->
          state

        app_id ->
          eff = effective_transform_values(state)

          live =
            %{
              orbit_rate: eff.orbit_rate,
              elev_base: eff.elev_base,
              roll_rate: eff.roll_rate,
              zoom_factor: eff.zoom_base,
              tilt_scale: eff.tilt_scale
            }

          live =
            if state.sat_auto do
              Map.put(live, :saturation_percent, effective_saturation_percent(state))
            else
              live
            end

          Phoenix.PubSub.broadcast(
            Octopus.PubSub,
            "apps",
            {:apps, {:transform_live, app_id, live}}
          )

          %State{state | transform_live_last_ms: now_ms}
      end
    else
      state
    end
  end

  defp advance_tick_state(%State{} = state) do
    panel_interaction_factors =
      Map.new(state.panel_interaction_factors, fn {i, value} ->
        target = if Map.get(state.buttons, i, false), do: 1.0, else: 0.0
        value = lerp(value, target, 0.05)
        {i, value}
      end)

    dt_signed = (1 / @fps) * param(:time_scale, 1.0) * state.speed * time_sign(state.time_direction)
    seconds = state.seconds + (1 / @fps) * param(:time_scale, 1.0) * state.speed
    formula_seconds = (state.formula_seconds || state.seconds) + dt_signed

    state = %State{
      state
      | seconds: seconds,
        formula_seconds: formula_seconds,
        panel_interaction_factors: panel_interaction_factors
    }

    state
    |> step_auto_wanderers()
    |> advance_octave_state_step()
    |> accumulate_orientation(dt_signed)
  end

  defp advance_octave_state_step(%State{} = state) do
    z = max(effective_transform_values(state).zoom_base || 1.0, @zoom_factor_min)
    {updates, _committed_n, _fade} = Zoom.advance_octave_state(state, z, state.seconds)
    struct(State, Map.merge(Map.from_struct(state), updates))
  end

  @doc false
  def accumulate_orientation_angles(yaw_angle, roll_angle, orbit_rate, roll_rate, dt_yaw, dt_roll) do
    {
      yaw_angle + orbit_rate * dt_yaw,
      roll_angle + roll_rate * dt_roll
    }
  end

  defp accumulate_orientation(%State{} = state, dt_signed) do
    eff = effective_transform_values(state)
    alpha = Sphere.alpha(Installation.width())
    # When trans_auto is on, eff.orbit_rate is 0 (pan replaces scroll), so yaw
    # stops integrating on its own — the pan lives in eff.yaw_offset instead.
    # When rot_auto is on, roll is driven directly by the sweep wanderer (an
    # eased absolute angle), not integrated from roll_rate.
    orbit_rad_s = eff.orbit_rate * alpha
    roll_rad_s = eff.roll_rate * :math.pi() / 180.0

    {yaw, roll_integrated} =
      accumulate_orientation_angles(
        state.yaw_angle || 0.0,
        state.roll_angle || 0.0,
        orbit_rad_s,
        roll_rad_s,
        dt_signed,
        dt_signed
      )

    roll = rot_sweep_angle(state) || roll_integrated

    %State{state | yaw_angle: yaw, roll_angle: roll}
  end

  defp rot_sweep_angle(%State{rot_auto: true} = state) do
    case state.auto_wanderers do
      %{rot: %{value: a}} when is_number(a) -> a
      _ -> nil
    end
  end

  defp rot_sweep_angle(_state), do: nil

  defp step_auto_wanderers(%State{} = state) do
    now = state.seconds

    {wanderers, rot_pivot} =
      Enum.reduce(@auto_channels, {state.auto_wanderers || %{}, state.rot_auto_pivot}, fn ch,
                                                                                          {acc,
                                                                                           pivot} ->
        if Map.get(state, :"#{ch}_auto") do
          interval = Map.get(state, :"#{ch}_auto_interval") || @auto_defaults[:"#{ch}_auto_interval"]
          w = Map.get(acc, ch) || new_channel_wanderer(state, ch)
          {_v, next} = step_channel_wanderer(w, now, state, ch, interval)
          # Rot keeps its pivot inside the sweeper (rerolled at the neutral point of
          # each new sweep); mirror it to state so build_motion_params can read it.
          next_pivot = if ch == :rot, do: Map.get(next, :pivot), else: pivot
          {Map.put(acc, ch, next), next_pivot}
        else
          {Map.delete(acc, ch), if(ch == :rot, do: nil, else: pivot)}
        end
      end)

    %State{state | auto_wanderers: wanderers, rot_auto_pivot: rot_pivot}
  end

  defp random_rot_pivot do
    (:rand.uniform(max(Installation.num_panels(), 1)) - 1) * 1.0
  end

  defp new_channel_wanderer(%State{} = state, :trans) do
    # X wanders a position offset centered on the current view (0); Y around elev_base.
    Wander.new({0.0, state.elev_base || 0.0})
  end

  defp new_channel_wanderer(%State{} = state, :zoom) do
    factor = max(state.zoom_base || 1.0, @zoom_factor_min)
    Wander.new(:math.log(factor))
  end

  defp new_channel_wanderer(%State{} = state, :sat) do
    Wander.new((state.saturation_percent || 70) * 1.0)
  end

  defp new_channel_wanderer(%State{} = state, :rot) do
    # Rot auto runs out-and-back sweeps: ease from baseline by ±θ and exactly back,
    # so each cycle returns to the start (no drift, no jump). A short pause upright
    # follows, then a new cycle rerolls θ/direction/pivot/duration/easing. Pivot is
    # rerolled at the neutral point so it never jumps visibly. First step (:pending)
    # rolls the initial sweep.
    base = state.roll_angle || 0.0

    %{
      baseline: base,
      amp: 0.0,
      pivot: nil,
      phase: :sweep,
      start: :pending,
      dur: 0.0,
      easing: :sine_in_out,
      value: base
    }
  end

  defp new_channel_wanderer(%State{} = state, ch) do
    Wander.new(Map.get(state, @channel_base_key[ch]) || 0.0)
  end

  defp step_channel_wanderer(w, now, state, :trans, interval) do
    # X pans a position offset around 0 (± range_x px); Y around elev_base (± range_y px).
    ey = state.elev_base || 0.0
    rx = Map.get(state, :trans_auto_range_x) || @auto_defaults.trans_auto_range_x
    ry = Map.get(state, :trans_auto_range_y) || @auto_defaults.trans_auto_range_y
    {lox, hix} = @channel_bounds.trans_x
    {loy, hiy} = @channel_bounds.trans_y

    Wander.step(w, now, %{
      mins: {max(-rx, lox), max(ey - ry, loy)},
      maxs: {min(rx, hix), min(ey + ry, hiy)},
      interval: interval,
      bias: :pingpong
    })
  end

  defp step_channel_wanderer(w, now, state, :zoom, interval) do
    b = max(state.zoom_base || 1.0, @zoom_factor_min)
    r = max(Map.get(state, :zoom_auto_range) || @auto_defaults.zoom_auto_range, 1.0)
    lo = max(:math.log(b / r), :math.log(@zoom_factor_min))
    hi = min(:math.log(b * r), :math.log(@zoom_factor_max))
    Wander.step(w, now, %{min: lo, max: hi, interval: interval, bias: :pingpong})
  end

  defp step_channel_wanderer(w, now, state, :sat, interval) do
    {lo, hi} = ordered_sat_bounds(state)
    Wander.step(w, now, %{min: lo, max: hi, interval: interval})
  end

  defp step_channel_wanderer(w, now, state, :rot, interval) do
    # Out-and-back cycle: :sweep eases baseline -> baseline±amp -> baseline (equal
    # halves, mirrored easing), then a new sweep is rolled immediately (no pause).
    # Value stays at baseline across boundaries -> seamless pivot changes.
    range_deg = Map.get(state, :rot_auto_range) || @auto_defaults.rot_auto_range

    case w.start do
      :pending ->
        next = roll_rot_sweep(w, now, interval, range_deg)
        {next.value, next}

      _ ->
        p = (now - w.start) / max(w.dur, 1.0e-9)
        e = if p < 0.5, do: Wander.ease(w.easing, p * 2.0), else: Wander.ease(w.easing, (1.0 - p) * 2.0)
        value = w.baseline + w.amp * e

        if p >= 1.0 do
          # Sweep finished exactly at baseline; roll the next one immediately.
          next = roll_rot_sweep(%{w | value: w.baseline}, now, interval, range_deg)
          {next.value, next}
        else
          {value, %{w | value: value}}
        end
    end
  end

  defp step_channel_wanderer(w, now, state, ch, interval) do
    base = Map.get(state, @channel_base_key[ch]) || 0.0
    range = Map.get(state, :"#{ch}_auto_range") || @auto_defaults[:"#{ch}_auto_range"]
    {lo, hi} = @channel_bounds[ch]
    min_v = max(base - range, lo)
    max_v = min(base + range, hi)
    Wander.step(w, now, %{min: min_v, max: max_v, interval: interval, bias: :pingpong})
  end

  # Roll a fresh out-and-back sweep: random magnitude (0.3..1.0 of range), random
  # direction, random duration (0.7..1.4 * interval), random easing, new pivot.
  defp roll_rot_sweep(w, now, interval, range_deg) do
    max_rad = range_deg * :math.pi() / 180.0
    sign = if :rand.uniform() < 0.5, do: -1.0, else: 1.0
    amp = sign * (0.3 + :rand.uniform() * 0.7) * max_rad
    dur = interval * (0.7 + :rand.uniform() * 0.7)
    easing = Enum.at(@rot_sweep_easings, :rand.uniform(length(@rot_sweep_easings)) - 1)

    %{
      w
      | amp: amp,
        pivot: random_rot_pivot(),
        phase: :sweep,
        start: now,
        dur: max(dur, 1.0e-9),
        easing: easing,
        value: w.baseline
    }
  end

  defp ordered_sat_bounds(%State{} = state) do
    {chan_lo, chan_hi} = @channel_bounds.sat
    a = Map.get(state, :sat_auto_min) || @auto_defaults.sat_auto_min
    b = Map.get(state, :sat_auto_max) || @auto_defaults.sat_auto_max
    lo = min(a, b) |> max(chan_lo) |> min(chan_hi)
    hi = max(a, b) |> max(chan_lo) |> min(chan_hi)
    {lo, hi}
  end

  defp push_frame(%State{} = state) do
    canvas = render(state)
    easing_interval = trunc(param(:easing_interval, 200))

    case state.color_mode do
      :white ->
        Octopus.App.update_display(canvas, :grayscale, easing_interval: easing_interval)

      _ ->
        Octopus.App.update_display(canvas, :rgb, easing_interval: easing_interval)
    end

    state
  end

  def handle_event(%AudioEvent{bass: low, mid: mid, high: high}, %State{} = state) do
    {:noreply, %State{state | audio_input: %{low: low, mid: mid, high: high}}}
  end

  def handle_event(
        %InputEvent{type: :button} = event,
        %State{} = state
      ) do
    pressed = event.action == :press
    {:noreply, %State{state | buttons: Map.put(state.buttons, event.button - 1, pressed)}}
  end

  def handle_event(%ProximityEvent{panel: panel} = event, %State{} = state) do
    distance = event.distance_combined
    distance_normalized = 1.0 - max(min(distance / 2500.0, 1.0), 0.0)

    panel_proximities =
      Map.update(
        state.panel_proximities,
        panel - 1,
        distance_normalized,
        &lerp(&1, distance_normalized, 0.5)
      )

    {:noreply, %State{state | panel_proximities: panel_proximities}}
  end

  def handle_event(_event, %State{} = state) do
    {:noreply, state}
  end

  @doc false
  def build_canvas(%State{} = state), do: render_canvas(state)

  defp render(%State{} = state), do: render_canvas(state)

  defp render_canvas(%State{display_info: display_info} = state) do
    # Deterministic motion (tilt) uses signed formula clock; auto wanderers use state.seconds.
    seconds = state.formula_seconds || state.seconds
    eff = effective_transform_values(state)
    z = max(eff.zoom_base || 1.0, @zoom_factor_min)
    motion_params = build_motion_params(state, seconds)
    zoom_branches = resolve_zoom_branches(state, z, seconds)

    canvas_mode = if state.color_mode == :white, do: :grayscale, else: :rgb
    canvas = Canvas.new(display_info.width, display_info.height, canvas_mode)
    saturation_percent = effective_saturation_percent(state)
    gain = value_gain(state)
    pattern_speed = state.pattern_speed || 1.0

    lerp_fn = fn a, b, v ->
      interpolate_colors_with_black(a, b, v, saturation_percent, gain)
    end

    panels = state.pixel_dirs || precompute_pixel_dirs()

    panels
    |> Enum.with_index()
    |> Enum.reduce(canvas, fn {panel, index}, canvas ->
      proximity = Map.get(state.panel_proximities, index, 0.0)
      hue_shift = proximity * 180 * 5
      interaction_factor = Map.get(state.panel_interaction_factors, index, 0.0)

      # pattern_speed scales formula time; interaction kick unscaled.
      pixel_time = seconds * pattern_speed + interaction_factor * 5

      audio = state.audio_input

      Enum.reduce(Enum.with_index(panel), canvas, fn {{x, y, d}, i}, canvas ->
        pixel =
          render_pixel(
            state,
            motion_params,
            z,
            zoom_branches,
            d,
            x,
            y,
            i,
            pixel_time,
            hue_shift,
            saturation_percent,
            gain,
            audio,
            lerp_fn
          )

        Canvas.put_pixel(canvas, {x, y}, pixel)
      end)
    end)
  end

  # Master pixel gain (0..100+): the per-scene Brightness slider multiplied onto
  # the hidden OSC value_percent (both default 100). Replaces the bare
  # value_percent read so Brightness scales every color mode.
  defp value_gain(%State{} = state) do
    param(:value_percent, 100) * (state.brightness_percent || 100) / 100.0
  end

  defp precompute_pixel_dirs do
    w = Installation.width()
    h = Installation.height()

    Installation.virtual_pixel_positions_per_panel()
    |> Enum.map(fn panel ->
      Enum.map(panel, fn {x, y} -> {x, y, Sphere.direction(x, y, w, h)} end)
    end)
  end

  @doc false
  def build_transform_params(state, seconds), do: build_motion_params(state, seconds)

  defp build_motion_params(%State{} = state, seconds) do
    w = Installation.width()
    h = Installation.height()
    alpha = Sphere.alpha(w)
    cx = w / 2 - 0.5
    cy = h / 2 - 0.5

    eff = effective_transform_values(state)
    orbit_rate = eff.orbit_rate
    roll_rate = eff.roll_rate
    tilt_scale = eff.tilt_scale
    elev_base = eff.elev_base
    z = max(eff.zoom_base || 1.0, @zoom_factor_min)

    # Orientation angles are already integrated in rad; fallback uses display→rad.
    # Translate auto adds a horizontal position offset (yaw_offset px → rad).
    yaw_angle = (state.yaw_angle || orbit_rate * alpha * seconds) + eff.yaw_offset * alpha
    roll_angle = state.roll_angle || roll_rate * :math.pi() / 180.0 * seconds

    # While frozen, slider deltas since the freeze scrub the still image.
    {yaw_angle, roll_angle} = frozen_scrub_angles(state, yaw_angle, roll_angle, alpha)

    neutral? =
      orbit_rate == 0.0 and roll_rate == 0.0 and tilt_scale == 0.0 and elev_base == 0.0 and
        z == 1.0 and (state.zoom_octave_n || 0) == 0 and state.octave_fade == nil and
        not any_auto?(state) and yaw_angle == 0.0 and roll_angle == 0.0

    if neutral? do
      %{neutral?: true, center_x: cx, center_y: cy, alpha: alpha}
    else
      tilt_amp_rad = tilt_scale * alpha
      roll_pivot_panel = if state.rot_auto, do: state.rot_auto_pivot || state.roll_pivot || 0, else: state.roll_pivot || 0
      roll_pivot_phi = panel_to_phi(roll_pivot_panel, w, alpha)
      zoom_pivot_phi = panel_to_phi(state.zoom_pivot || 0, w, alpha)
      x_p = zoom_pivot_phi / alpha

      matrix =
        Sphere.orientation(
          yaw: yaw_angle,
          roll_angle: roll_angle,
          roll_pivot_phi: roll_pivot_phi,
          tilt_amplitude: tilt_amp_rad,
          tilt_speed: state.tilt_speed || @tilt_defaults.tilt_speed,
          tilt_mode: state.tilt_mode || @tilt_defaults.tilt_mode,
          t: seconds
        )

      %{
        neutral?: false,
        matrix: matrix,
        mobius_basis: Sphere.mobius_basis(zoom_pivot_phi),
        elev_rad: Sphere.elev_offset(elev_base, alpha),
        alpha: alpha,
        center_x: cx,
        center_y: cy,
        x_p: x_p
      }
    end
  end

  defp resolve_zoom_branches(%State{} = state, z, seconds) do
    current_n = state.zoom_octave_n || 0

    cond do
      state.time_frozen ->
        {n, _r} = Zoom.decompose(z, current_n)
        {:steady, n}

      state.octave_fade == nil ->
        {:steady, current_n}

      true ->
        fade = state.octave_fade
        u = Zoom.fade_u(fade, seconds)

        if u >= 1.0 do
          {:steady, fade.to_n}
        else
          {:fade, fade.from_n, fade.to_n, u}
        end
    end
  end

  defp render_pixel(
         state,
         motion_params,
         z,
         zoom_branches,
         d,
         x,
         y,
         i,
         pixel_time,
         hue_shift,
         saturation_percent,
         gain,
         audio,
         lerp_fn
       ) do
    sample_ctx = {motion_params, z, x, y, d}

    case zoom_branches do
      {:steady, n} ->
        sample_ctx
        |> sample_zoom_branch(n)
        |> colorize_sample(state, i, pixel_time, hue_shift, saturation_percent, gain, audio, lerp_fn)

      {:fade, from_n, to_n, u} ->
        c_from =
          sample_ctx
          |> sample_zoom_branch(from_n)
          |> colorize_sample(state, i, pixel_time, hue_shift, saturation_percent, gain, audio, lerp_fn)

        c_to =
          sample_ctx
          |> sample_zoom_branch(to_n)
          |> colorize_sample(state, i, pixel_time, hue_shift, saturation_percent, gain, audio, lerp_fn)

        blend_pixels(c_from, c_to, u)
    end
  end

  defp sample_zoom_branch({motion_params, z, x, y, d}, n) do
    m = Zoom.octave_factor(n)
    r = z / m

    if motion_params.neutral? do
      {xs, ys, dir} = Sphere.sample(d, Map.merge(motion_params, %{x: x, y: y}))
      {xs, ys, dir}
    else
      Zoom.sample_pixel(d, motion_params, m, r, motion_params.x_p)
    end
  end

  defp colorize_sample({x_scaled, y_scaled, {nx, ny, nz}}, state, i, pixel_time, hue_shift, sat, gain, audio, lerp_fn) do
    case state.color_mode do
      :white ->
        {color_a, color_b} = state.colors

        state.program
        |> eval_pixel_value(
          x_scaled,
          y_scaled,
          nx,
          ny,
          nz,
          i,
          pixel_time,
          audio.low,
          audio.mid,
          audio.high
        )
        |> white_pixel_value(color_a, color_b, gain)

      :rainbow ->
        value =
          eval_pixel_value(
            state.program,
            x_scaled,
            y_scaled,
            nx,
            ny,
            nz,
            i,
            pixel_time,
            audio.low,
            audio.mid,
            audio.high
          )

        rainbow_pixel_color(x_scaled, y_scaled, value, hue_shift, sat, gain)

      _ ->
        {color_a, color_b} = state.colors

        colors = {
          %Chameleon.HSV{(%Chameleon.HSV{} = color_a) | h: rem(trunc(color_a.h + hue_shift), 360)},
          %Chameleon.HSV{(%Chameleon.HSV{} = color_b) | h: rem(trunc(color_b.h + hue_shift), 360)}
        }

        pixels(
          state.program,
          x_scaled,
          y_scaled,
          nx,
          ny,
          nz,
          i,
          pixel_time,
          audio.low,
          audio.mid,
          audio.high,
          colors,
          lerp_fn
        )
    end
  end

  defp blend_pixels(c_from, c_to, u) when is_integer(c_from) and is_integer(c_to) do
    round((1 - u) * c_from + u * c_to)
  end

  defp blend_pixels({r1, g1, b1}, {r2, g2, b2}, u) do
    {
      round((1 - u) * r1 + u * r2),
      round((1 - u) * g1 + u * g2),
      round((1 - u) * b1 + u * b2)
    }
  end

  defp panel_to_phi(panel, w, alpha) do
    n = max(Installation.num_panels(), 1)
    panel = panel |> trunc() |> max(0) |> min(n - 1)
    stride = Installation.panel_width() + Installation.panel_gap()
    cx = w / 2 - 0.5
    center_x = panel * stride + Installation.panel_width() / 2 - 0.5
    (center_x - cx) * alpha
  end

  defp sample_pixel(d, x, y, motion_params, z, n) do
    {xs, ys, _dir} =
      {motion_params, z, x, y, d}
      |> sample_zoom_branch(n)

    {xs, ys}
  end

  @doc false
  def transform_pixel_coords(x, y, params) do
    w = Installation.width()
    h = Installation.height()
    d = Map.get(params, :direction) || Sphere.direction(x, y, w, h)

    motion_params =
      case params do
        %{neutral?: _} = p ->
          p

        _ ->
          motion =
            default_motion_state()
            |> Map.merge(Map.take(params, Map.keys(default_motion_state())))

          state_like = struct(State, Map.put(motion, :zoom_octave_n, Map.get(params, :zoom_octave_n, 0)))
          build_motion_params(state_like, Map.get(params, :seconds, 0.0))
      end

    z = max(Map.get(params, :zoom_base, 1.0), @zoom_factor_min)
    current_n = Map.get(params, :zoom_octave_n, 0)
    {n, _r} = Zoom.decompose(z, current_n)

    sample_pixel(d, x, y, motion_params, z, n)
  end

  defp default_motion_state do
    %{
      orbit_rate: 0.0,
      roll_rate: 0.0,
      roll_pivot: 0,
      tilt_scale: 0.0,
      tilt_speed: 0.5,
      tilt_mode: :wobble,
      elev_base: 0.0,
      zoom_base: 1.0,
      zoom_pivot: 0,
      zoom_octave_n: 0,
      octave_fade: nil,
      pattern_speed: 1.0,
      trans_auto: false,
      rot_auto: false,
      zoom_auto: false,
      sway_auto: false,
      sat_auto: false,
      yaw_angle: nil,
      roll_angle: nil,
      auto_wanderers: %{}
    }
  end

  defp auto_config_from_state(%State{} = state) do
    Enum.reduce(@auto_channels, %{}, fn ch, acc ->
      acc =
        acc
        |> Map.put(:"#{ch}_auto", Map.get(state, :"#{ch}_auto") || false)
        |> Map.put(
          :"#{ch}_auto_interval",
          Map.get(state, :"#{ch}_auto_interval") || @auto_defaults[:"#{ch}_auto_interval"]
        )

      case ch do
        :trans ->
          acc
          |> Map.put(
            :trans_auto_range_x,
            Map.get(state, :trans_auto_range_x) || @auto_defaults.trans_auto_range_x
          )
          |> Map.put(
            :trans_auto_range_y,
            Map.get(state, :trans_auto_range_y) || @auto_defaults.trans_auto_range_y
          )

        :sat ->
          acc
          |> Map.put(:sat_auto_min, Map.get(state, :sat_auto_min) || @auto_defaults.sat_auto_min)
          |> Map.put(:sat_auto_max, Map.get(state, :sat_auto_max) || @auto_defaults.sat_auto_max)

        _ ->
          Map.put(
            acc,
            :"#{ch}_auto_range",
            Map.get(state, :"#{ch}_auto_range") || @auto_defaults[:"#{ch}_auto_range"]
          )
      end
    end)
  end

  defp put_auto_fields(%State{} = state, config) do
    Enum.reduce(@auto_channels, state, fn ch, acc ->
      auto_key = :"#{ch}_auto"
      interval_key = :"#{ch}_auto_interval"

      acc =
        acc
        |> Map.put(
          auto_key,
          coerce_boolean(Map.get(config, auto_key, Map.get(acc, auto_key) || false))
        )
        |> Map.put(
          interval_key,
          Map.get(config, interval_key, Map.get(acc, interval_key) || @auto_defaults[interval_key])
        )

      case ch do
        :trans ->
          acc
          |> Map.put(
            :trans_auto_range_x,
            Map.get(
              config,
              :trans_auto_range_x,
              Map.get(acc, :trans_auto_range_x) || @auto_defaults.trans_auto_range_x
            )
          )
          |> Map.put(
            :trans_auto_range_y,
            Map.get(
              config,
              :trans_auto_range_y,
              Map.get(acc, :trans_auto_range_y) || @auto_defaults.trans_auto_range_y
            )
          )

        :sat ->
          acc
          |> Map.put(
            :sat_auto_min,
            Map.get(config, :sat_auto_min, Map.get(acc, :sat_auto_min) || @auto_defaults.sat_auto_min)
          )
          |> Map.put(
            :sat_auto_max,
            Map.get(config, :sat_auto_max, Map.get(acc, :sat_auto_max) || @auto_defaults.sat_auto_max)
          )

        _ ->
          range_key = :"#{ch}_auto_range"

          Map.put(
            acc,
            range_key,
            Map.get(config, range_key, Map.get(acc, range_key) || @auto_defaults[range_key])
          )
      end
    end)
  end

  defp auto_flags(%State{} = state) do
    Map.new(@auto_channels, fn ch -> {ch, Map.get(state, :"#{ch}_auto") || false} end)
  end

  defp init_auto_wanderers(%State{} = state) do
    wanderers =
      Enum.reduce(@auto_channels, %{}, fn ch, acc ->
        if Map.get(state, :"#{ch}_auto") do
          Map.put(acc, ch, new_channel_wanderer(state, ch))
        else
          acc
        end
      end)

    %State{state | auto_wanderers: wanderers}
  end

  defp sync_auto_wanderers(%State{} = state, old_flags) do
    {wanderers, %State{} = state} =
      Enum.reduce(@auto_channels, {state.auto_wanderers || %{}, state}, fn ch, {acc, st} ->
        was = Map.get(old_flags, ch, false)
        now? = Map.get(st, :"#{ch}_auto") || false

        cond do
          now? and not was ->
            {Map.put(acc, ch, new_channel_wanderer(st, ch)), st}

          not now? and was ->
            st = handover_wanderer_value(st, ch, Map.get(acc, ch))
            {Map.delete(acc, ch), st}

          true ->
            {acc, st}
        end
      end)

    state = %State{state | auto_wanderers: wanderers}

    turned_off? =
      Enum.any?(@auto_channels, fn ch ->
        Map.get(old_flags, ch, false) and not (Map.get(state, :"#{ch}_auto") || false)
      end)

    if turned_off?, do: broadcast_config(state)
    state
  end

  # Auto OFF resets the channel to its base/preset value: the wanderer is dropped
  # (by the caller) and no live value is baked in. Only rot needs an explicit
  # reset because it is the only channel whose integrated state (roll_angle) is
  # driven per-tick while auto is on; every other channel keeps its untouched base
  # in state and simply stops using the (now removed) wander.
  defp handover_wanderer_value(%State{} = state, :rot, _) do
    %State{state | roll_angle: 0.0, rot_auto_pivot: nil}
  end

  defp handover_wanderer_value(%State{} = state, _ch, _), do: state

  defp any_auto?(%State{} = state) do
    Enum.any?(@auto_channels, &(Map.get(state, :"#{&1}_auto") || false))
  end

  defp effective_saturation_percent(%State{} = state) do
    base = state.saturation_percent || 70

    if state.sat_auto do
      case state.auto_wanderers do
        %{sat: %Wander{value: {v}}} -> coerce_saturation_percent(v)
        _ -> base
      end
    else
      base
    end
  end

  defp effective_transform_values(%State{} = state) do
    orbit = state.orbit_rate || 0.0
    elev = state.elev_base || 0.0
    roll = state.roll_rate || 0.0
    zoom = state.zoom_base || 1.0
    sway = state.tilt_scale || 0.0

    # Translate auto pans a horizontal position offset (yaw_offset, px) instead
    # of driving the scroll rate — so the manual orbit_rate scroll is suppressed
    # while auto is on. yaw_offset (X) and elev_base (Y) are both positions.
    {orbit, yaw_offset, elev} =
      if state.trans_auto do
        case state.auto_wanderers do
          %{trans: %Wander{value: {ox, ey}}} -> {0.0, ox, ey}
          _ -> {orbit, 0.0, elev}
        end
      else
        {orbit, 0.0, elev}
      end

    wander_val = fn ch, base ->
      if Map.get(state, :"#{ch}_auto") do
        case state.auto_wanderers do
          %{^ch => %Wander{value: {v}}} ->
            if ch == :zoom, do: :math.exp(v), else: v

          _ ->
            base
        end
      else
        base
      end
    end

    # Rot auto drives roll via the sweep angle (see accumulate_orientation), so the
    # manual roll_rate is suppressed while auto is on — same idea as orbit/trans.
    %{
      orbit_rate: orbit,
      yaw_offset: yaw_offset,
      elev_base: elev,
      roll_rate: if(state.rot_auto, do: 0.0, else: roll),
      zoom_base: wander_val.(:zoom, zoom),
      tilt_scale: wander_val.(:sway, sway)
    }
  end

  @default_env %{
    ~c"pi" => :math.pi(),
    ~c"PI" => :math.pi(),
    ~c"tau" => :math.pi() * 2,
    ~c"Tau" => :math.pi() * 2
  }

  def pixels(expr, x, y, i, t, color_a, color_b, lerp_fn \\ &interpolate_colors_with_black/3)

  def pixels(expr, x, y, i, t, color_a, color_b, lerp_fn)
      when is_binary(expr) do
    {:ok, program} = Program.parse(expr)
    pixels(program, x, y, i, t, color_a, color_b, lerp_fn)
  end

  def pixels(program, x, y, i, t, color_a, color_b, lerp_fn) do
    pixels(program, x, y, 0.0, 0.0, 1.0, i, t, 0, 0, 0, {color_a, color_b}, lerp_fn)
  end

  def pixels(expr, x, y, i, t, l, m, h, {{r1, g1, b1}, {r2, g2, b2}}, lerp_fn) do
    pixels(
      expr,
      x,
      y,
      0.0,
      0.0,
      1.0,
      i,
      t,
      l,
      m,
      h,
      {Chameleon.RGB.new(r1, g1, b1) |> Chameleon.convert(Chameleon.HSV),
       Chameleon.RGB.new(r2, g2, b2) |> Chameleon.convert(Chameleon.HSV)},
      lerp_fn
    )
  end

  def pixels(expr, x, y, i, t, l, m, h, {color_a, color_b}, lerp_fn) do
    pixels(expr, x, y, 0.0, 0.0, 1.0, i, t, l, m, h, {color_a, color_b}, lerp_fn)
  end

  def pixels(expr, x, y, nx, ny, nz, i, t, l, m, h, {color_a, color_b}, lerp_fn) do
    env = [
      %{
        ~c"x" => x,
        ~c"y" => y,
        ~c"nx" => nx,
        ~c"ny" => ny,
        ~c"nz" => nz,
        ~c"i" => i,
        ~c"t" => t,
        ~c"l" => l,
        ~c"m" => m,
        ~c"h" => h
      },
      @default_env
    ]

    value =
      expr
      |> Program.eval(env)
      |> max(-1.0)
      |> min(1.0)

    lerp_fn.(color_a, color_b, value)
  end

  defp eval_pixel_value(expr, x, y, nx, ny, nz, i, t, l, m, h) do
    env = [
      %{
        ~c"x" => x,
        ~c"y" => y,
        ~c"nx" => nx,
        ~c"ny" => ny,
        ~c"nz" => nz,
        ~c"i" => i,
        ~c"t" => t,
        ~c"l" => l,
        ~c"m" => m,
        ~c"h" => h
      },
      @default_env
    ]

    expr
    |> Program.eval(env)
    |> max(-1.0)
    |> min(1.0)
  end

  defp white_pixel_value(value, %Chameleon.HSV{v: level_a}, %Chameleon.HSV{v: level_b}, gain) do
    level =
      cond do
        value > 0 -> level_a * value
        value < 0 -> level_b * -value
        true -> 0
      end

    level
    |> Kernel.*(gain / 100.0)
    |> Kernel.*(255 / 100.0)
    |> round()
    |> max(0)
    |> min(255)
  end

  defp rainbow_pixel_color(_x, _y, value, _hue_shift, _saturation_percent, _gain) when value == 0.0,
    do: {0, 0, 0}

  defp rainbow_pixel_color(x, y, value, hue_shift, saturation_percent, gain) do
    hue = rainbow_hue(x, y, hue_shift)

    saturation = saturation_percent |> max(0) |> min(100)
    brightness = trunc(gain * abs(value)) |> max(0) |> min(100)

    %Chameleon.RGB{r: r, g: g, b: b} =
      Chameleon.HSV.new(hue, saturation, brightness) |> Chameleon.convert(Chameleon.RGB)

    {r, g, b}
  end

  # Spread hue evenly across pattern space (both axes). Pure atan2 clusters
  # two colours on flat/circular layouts where one axis barely varies.
  defp rainbow_hue(x, y, hue_shift) do
    w = max(Installation.width(), 1) * 1.0
    h = max(Installation.height(), 1) * 1.0

    x_frac = (x + w / 2) / w
    y_frac = (y + h / 2) / h

    hue = x_frac * 240.0 + y_frac * 120.0 + hue_shift
    hue = :math.fmod(hue, 360.0)
    hue = if hue < 0, do: hue + 360.0, else: hue

    trunc(hue)
  end

  defp interpolate_colors_with_black(%Chameleon.HSV{} = a, %Chameleon.HSV{} = b, value),
    do: interpolate_colors_with_black(a, b, value, 70)

  defp interpolate_colors_with_black(%Chameleon.HSV{} = a, %Chameleon.HSV{} = b, value, saturation_percent),
    do: interpolate_colors_with_black(a, b, value, saturation_percent, param(:value_percent, 100))

  defp interpolate_colors_with_black(%Chameleon.HSV{} = a, %Chameleon.HSV{} = b, value, saturation_percent, gain) do
    saturation = saturation_percent |> max(0) |> min(100)

    hsv =
      cond do
        value > 0 ->
          %Chameleon.HSV{
            a
            | s: saturation,
              v: trunc(gain * value) |> max(0) |> min(100)
          }

        value < 0 ->
          %Chameleon.HSV{
            b
            | s: saturation,
              v: trunc(gain * -value) |> max(0) |> min(100)
          }

        true ->
          %Chameleon.HSV{h: 0, s: 0, v: 0}
      end

    hsv = %Chameleon.HSV{hsv | h: hsv.h |> max(0) |> min(359)}

    %Chameleon.RGB{r: r, g: g, b: b} = Chameleon.convert(hsv, Chameleon.RGB)
    {r, g, b}
  end

  defp lerp(a, b, t) do
    (1 - t) * a + t * b
  end

  defp advance_palette_colors(%State{color_mode: mode} = state) when mode in [:random, :white] do
    state
    |> lerp_toward_target_colors()
    |> maybe_swap_palette()
  end

  defp advance_palette_colors(%State{} = state), do: state

  # Crossfade the live pair from last_colors toward target_colors across one
  # color_interval, mirroring the original PixelFun. Progress is derived from the
  # remaining lerp_time so the fade finishes exactly as the next swap is due.
  defp lerp_toward_target_colors(%State{} = state) do
    interval = palette_interval_s(state)
    current = max(interval - (state.lerp_time || 0.0), 0.0)
    t = current / interval
    lerp_time = max((state.lerp_time || 0.0) - 1 / @fps, 0.0)

    {last_a, last_b} = state.last_colors
    {target_a, target_b} = state.target_colors
    new_a = lerp_hsv(last_a, target_a, t)
    new_b = lerp_hsv(last_b, target_b, t)

    %State{state | colors: {new_a, new_b}, lerp_time: lerp_time}
  end

  # With Auto (palette_auto) on, roll a fresh random pair the moment the current
  # crossfade completes. Auto off leaves the pair static (needed for presets like
  # wabengitter that rely on two frozen colours).
  defp maybe_swap_palette(%State{} = state) do
    if palette_auto_on?(state) and (state.lerp_time || 0.0) <= 0.0 do
      target = generate_random_palette(state.color_mode, state.saturation_percent)

      %State{
        state
        | last_colors: state.colors,
          target_colors: target,
          lerp_time: palette_interval_s(state)
      }
    else
      state
    end
  end

  defp apply_palette_colors(%State{color_mode: mode} = state) when mode in [:random, :white] do
    palette = generate_random_palette(mode, state.saturation_percent)

    %State{
      state
      | colors: palette,
        last_colors: palette,
        target_colors: palette,
        lerp_time: palette_interval_s(state)
    }
  end

  defp apply_palette_colors(%State{} = state), do: state

  defp palette_interval_s(%State{} = state), do: palette_interval_s(state.color_interval)
  defp palette_interval_s(interval) when is_number(interval), do: max(interval, 0.1)
  defp palette_interval_s(_), do: 5.0

  # Interpolate in RGB space then return HSV so the render path (which expects
  # %Chameleon.HSV{}) keeps working for both hue pairs and white levels.
  defp lerp_hsv(a, b, value) do
    a_rgb = Chameleon.convert(a, Chameleon.RGB)
    b_rgb = Chameleon.convert(b, Chameleon.RGB)

    r = lerp(a_rgb.r, b_rgb.r, value) |> trunc()
    g = lerp(a_rgb.g, b_rgb.g, value) |> trunc()
    bl = lerp(a_rgb.b, b_rgb.b, value) |> trunc()

    Chameleon.RGB.new(r, g, bl) |> Chameleon.convert(Chameleon.HSV)
  end

  defp generate_random_palette(:white, _saturation_percent), do: generate_random_white_levels()

  defp generate_random_palette(_color_mode, saturation_percent),
    do: generate_random_colors(saturation_percent)

  @doc false
  def generate_random_white_levels do
    low_max = 100 - @min_white_level_gap
    low = @min_white_level + :rand.uniform(low_max - @min_white_level + 1) - 1
    extra = 100 - low - @min_white_level_gap

    high =
      if extra <= 0 do
        100
      else
        low + @min_white_level_gap + :rand.uniform(extra)
      end

    {a, b} =
      case :rand.uniform(2) do
        1 -> {low, high}
        2 -> {high, low}
      end

    {%Chameleon.HSV{h: 0, s: 0, v: a}, %Chameleon.HSV{h: 0, s: 0, v: b}}
  end

  # Random pair with a guaranteed minimum 60° hue gap (up to 239°), matching the
  # original PixelFun. Saturation is (re)applied at render time.
  @doc false
  def generate_random_colors(saturation_percent) do
    hue_a = :rand.uniform(360) - 1
    hue_b = Integer.mod(hue_a + 60 + :rand.uniform(180) - 1, 360)
    sat = saturation_percent |> max(0) |> min(100)
    {Chameleon.HSV.new(hue_a, sat, 100), Chameleon.HSV.new(hue_b, sat, 100)}
  end
end
