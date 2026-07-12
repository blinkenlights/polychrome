defmodule Octopus.Apps.PixelFun do
  use Octopus.App, category: :interactive
  use Octopus.Params, prefix: :pixelfun

  require Logger

  alias Octopus.Canvas
  alias Octopus.Events.Event.Audio, as: AudioEvent
  alias Octopus.Events.Event.Input, as: InputEvent
  alias Octopus.Events.Event.Proximity, as: ProximityEvent
  alias Octopus.AppSupervisor
  alias Octopus.Apps.PixelFun.Program
  alias Octopus.Installation
  alias Octopus.Sphere
  alias Octopus.Wander

  @app_mode_presets "Elixir.Octopus.AppModePresets"

  @auto_channels [:trans, :rot, :zoom, :sway]

  @auto_defaults %{
    trans_auto: false,
    trans_auto_range_x: 1.0,
    trans_auto_range_y: 2.0,
    trans_auto_interval: 30.0,
    rot_auto: false,
    rot_auto_range: 1.0,
    rot_auto_interval: 30.0,
    zoom_auto: false,
    zoom_auto_range: 0.8,
    zoom_auto_interval: 30.0,
    sway_auto: false,
    sway_auto_range: 2.0,
    sway_auto_interval: 30.0
  }

  @channel_bounds %{
    trans_x: {-4.0, 4.0},
    trans_y: {-4.0, 4.0},
    rot: {-4.0, 4.0},
    zoom: {-2.0, 2.0},
    sway: {0.0, 4.0}
  }

  @channel_base_key %{
    rot: :roll_rate,
    zoom: :zoom_base,
    sway: :tilt_scale
  }

  @default_scene %{
    color_mode: :random,
    saturation_percent: 70,
    palette_phase: 0.0,
    color_interval: 5.0,
    palette_auto: true,
    orbit_rate: 0.0,
    roll_rate: 0.0,
    roll_pivot: 0,
    tilt_scale: 0.0,
    tilt_speed: 0.5,
    tilt_mode: :wobble,
    elev_base: 0.0,
    zoom_base: 0.0,
    zoom_pivot: 0,
    pattern_speed: 1.0,
    time_direction: :forward
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
                        :palette_phase,
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
      formula: "sin(x*y*0.06+sin(t*0.2)*x*0.2-t*0.4)*cos(hypot(x,y)*2+t*0.2)",
      accent_color: "#2ECC71"
    },
    %{
      slug: "swaytest",
      name: "Swaytest",
      formula: "(tanh((y-0.3)*4)+tanh((y+0.3)*4))/2",
      accent_color: "#FF7043"
    }
  ]

  @fps 60
  @frame_time_ms trunc(1000 / @fps)
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
      :auto_wanderers,
      :yaw_angle,
      :roll_angle,
      :time_direction,
      :color_mode,
      :saturation_percent,
      :palette_phase,
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
      :show_advanced
    ]
  end

  def name(), do: "Pixel Fun"

  def compatible?() do
    Octopus.App.get_installation_info().panel_count >= 1
  end

  def config_schema() do
    %{
      program: {"Formula", :string, %{default: "sin(0.4*t-hypot(x,y))"}},
      color_mode: {"Colors", :atom, %{default: :random}},
      saturation_percent: {"Saturation", :int, %{default: 70, min: 0, max: 100}},
      palette_phase: {"Palette", :float, %{default: 0.0, min: 0.0, max: 1.0, step: 0.01}},
      color_interval: {"Palette tempo (s)", :float, %{default: 5, min: 1, max: 20, step: 0.5}},
      palette_auto: {"Palette Auto", :boolean, %{default: true}},
      orbit_rate: {"Translate X", :float, %{default: 0.0, min: -4, max: 4, step: 0.01}},
      elev_base: {"Translate Y", :float, %{default: 0.0, min: -4, max: 4, step: 0.1}},
      roll_rate: {"Rotation", :float, %{default: 0.0, min: -4, max: 4, step: 0.01}},
      zoom_base: {"Zoom", :float, %{default: 0.0, min: -2, max: 2, step: 0.05}},
      tilt_scale: {"Sway", :float, %{default: 0.0, min: 0, max: 4, step: 0.1}},
      trans_auto: {"Translate Auto", :boolean, %{default: false}},
      trans_auto_range_x: {"Translate Range X", :float, %{default: 1.0, min: 0, max: 4, step: 0.05}},
      trans_auto_range_y: {"Translate Range Y", :float, %{default: 2.0, min: 0, max: 4, step: 0.05}},
      trans_auto_interval: {"Translate Interval", :float, %{default: 30.0, min: 4, max: 60, step: 1}},
      rot_auto: {"Rotation Auto", :boolean, %{default: false}},
      rot_auto_range: {"Rotation Range", :float, %{default: 1.0, min: 0, max: 4, step: 0.05}},
      rot_auto_interval: {"Rotation Interval", :float, %{default: 30.0, min: 4, max: 60, step: 1}},
      zoom_auto: {"Zoom Auto", :boolean, %{default: false}},
      zoom_auto_range: {"Zoom Range", :float, %{default: 0.8, min: 0, max: 2, step: 0.05}},
      zoom_auto_interval: {"Zoom Interval", :float, %{default: 30.0, min: 4, max: 60, step: 1}},
      sway_auto: {"Sway Auto", :boolean, %{default: false}},
      sway_auto_range: {"Sway Range", :float, %{default: 2.0, min: 0, max: 4, step: 0.05}},
      sway_auto_interval: {"Sway Interval", :float, %{default: 30.0, min: 4, max: 60, step: 1}},
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

    Colors — Random dual maps positive/negative lobes to a complementary hue pair on the colour circle; scrub Palette to pick the hue, Auto advances it (Tempo = seconds per full circle). Rainbow spreads hue across the pattern (moves with orbit/rotation). White dual maps lobes to two brightness levels on the warm W channel of the TM1814 LEDs (no RGB tint); Palette/Auto work the same for brightness pairs.

    Saturation — colour vividness for Random dual and Rainbow (0 = grey, 100 = full; default 70). White dual ignores saturation.

    Translate X — yaw orbit of the pattern around the ring (seamless). Looks like horizontal drift from inside the ring. Auto wanders the rate.

    Translate Y — static vertical band shift (seamless in azimuth). Auto wanders the offset.

    Rotation — roll about a panel pivot; the pattern spins around that panel. Auto wanders the rate. Rotation pivot (Advanced) selects which panel.

    Zoom — conformal Möbius dilation toward the zoom pivot panel (static log-zoom). Auto wanders the zoom value.

    Sway — small-angle tilt about a horizontal axis (Wobble precesses; Pendulum oscillates amplitude). Strength is in pixel units. Auto wanders strength; Sway speed/mode live in Advanced.

    Time direction — forward (default) or backward. Backward reverses formula animation and manual sphere motion. Auto wanderers and palette Auto ignore time direction (they keep advancing on wall-clock app time).

    Scenes — pick a scene to play it on the wall. Add scenes to the queue to rotate through them at the chosen interval.
    """
  end

  def get_config(state) do
    scene =
      %{
        program: state.source,
        color_mode: state.color_mode,
        saturation_percent: state.saturation_percent,
        palette_phase: state.palette_phase || 0.0,
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
      show_advanced: state.show_advanced || false
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

    channel_bit = fn ch, label, key ->
      if Map.get(config, :"#{ch}_auto", false) do
        case ch do
          :trans ->
            "trans auto±#{format_num(Map.get(config, :trans_auto_range_x, 0))}/#{format_num(Map.get(config, :trans_auto_range_y, 0))}"

          _ ->
            "#{label} auto±#{format_num(Map.get(config, :"#{ch}_auto_range", 0))}"
        end
      else
        "#{label} #{format_num(Map.get(config, key, 0))}"
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
            "white #{format_phase(config[:palette_phase])}"
          end

        _ ->
          if Map.get(config, :palette_auto, true) do
            "palette auto #{format_num(config[:color_interval])}s"
          else
            "palette #{format_phase(config[:palette_phase])}"
          end
      end

    sliders =
      Enum.join(
        [
          if Map.get(config, :trans_auto, false) do
            channel_bit.(:trans, "trans", :orbit_rate)
          else
            [
              channel_bit.(:trans, "tx", :orbit_rate),
              "ty #{format_num(Map.get(config, :elev_base, 0))}"
            ]
            |> Enum.join(" · ")
          end,
          channel_bit.(:rot, "rot", :roll_rate),
          channel_bit.(:zoom, "zoom", :zoom_base),
          channel_bit.(:sway, "sway", :tilt_scale),
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

  defp format_phase(nil), do: "0°"
  defp format_phase(phase) when is_number(phase), do: "#{trunc(wrap_unit(phase) * 360)}°"
  defp format_phase(_), do: "0°"

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
        key: :saturation_percent,
        label: "Saturation",
        type: :slider,
        min: 0,
        max: 100,
        step: 1,
        default: 70,
        visible_when: {:color_mode, [:random, :rainbow]}
      },
      %{
        key: :palette_phase,
        label: "Palette",
        type: :slider,
        min: 0.0,
        max: 1.0,
        step: 0.01,
        default: 0.0,
        auto_key: :palette_auto,
        visible_when: {:color_mode, [:random, :white]}
      },
      %{
        key: :palette_auto,
        label: "Auto",
        type: :toggle,
        default: true,
        companion_of: :palette_phase
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
        min: -4.0,
        max: 4.0,
        step: 0.01,
        default: 0.0,
        auto_key: :trans_auto
      },
      %{key: :trans_auto, label: "Auto", type: :toggle, default: false, companion_of: :orbit_rate},
      %{
        key: :trans_auto_range_x,
        label: "Range X",
        type: :slider,
        min: 0.0,
        max: 4.0,
        step: 0.05,
        default: 1.0,
        visible_when: {:trans_auto, [true]}
      },
      %{
        key: :trans_auto_range_y,
        label: "Range Y",
        type: :slider,
        min: 0.0,
        max: 4.0,
        step: 0.05,
        default: 2.0,
        visible_when: {:trans_auto, [true]}
      },
      %{
        key: :trans_auto_interval,
        label: "Interval",
        type: :slider,
        min: 4.0,
        max: 60.0,
        step: 1.0,
        default: 30.0,
        unit: "s",
        visible_when: {:trans_auto, [true]}
      },
      %{
        key: :elev_base,
        label: "Translate Y",
        type: :slider,
        min: -4.0,
        max: 4.0,
        step: 0.1,
        default: 0.0
      },
      %{
        key: :roll_rate,
        label: "Rotation",
        type: :slider,
        min: -4.0,
        max: 4.0,
        step: 0.01,
        default: 0.0,
        auto_key: :rot_auto
      },
      %{key: :rot_auto, label: "Auto", type: :toggle, default: false, companion_of: :roll_rate},
      %{
        key: :rot_auto_range,
        label: "Range",
        type: :slider,
        min: 0.0,
        max: 4.0,
        step: 0.05,
        default: 1.0,
        visible_when: {:rot_auto, [true]}
      },
      %{
        key: :rot_auto_interval,
        label: "Interval",
        type: :slider,
        min: 4.0,
        max: 60.0,
        step: 1.0,
        default: 30.0,
        unit: "s",
        visible_when: {:rot_auto, [true]}
      },
      %{
        key: :zoom_base,
        label: "Zoom",
        type: :slider,
        min: -2.0,
        max: 2.0,
        step: 0.05,
        default: 0.0,
        auto_key: :zoom_auto
      },
      %{key: :zoom_auto, label: "Auto", type: :toggle, default: false, companion_of: :zoom_base},
      %{
        key: :zoom_auto_range,
        label: "Range",
        type: :slider,
        min: 0.0,
        max: 2.0,
        step: 0.05,
        default: 0.8,
        visible_when: {:zoom_auto, [true]}
      },
      %{
        key: :zoom_auto_interval,
        label: "Interval",
        type: :slider,
        min: 4.0,
        max: 60.0,
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
        auto_key: :sway_auto
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
        visible_when: {:sway_auto, [true]}
      },
      %{
        key: :sway_auto_interval,
        label: "Interval",
        type: :slider,
        min: 4.0,
        max: 60.0,
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

    :timer.send_interval(@frame_time_ms, :tick)
    color_mode = Map.get(config, :color_mode, :random)
    saturation_percent = Map.get(config, :saturation_percent, 70)
    palette_phase = coerce_palette_phase(Map.get(config, :palette_phase, 0.0))
    palette = palette_from_phase(palette_phase, color_mode, saturation_percent)
    time_frozen = Map.get(config, :time_frozen, false) |> coerce_time_frozen()

    palette_auto = Map.get(config, :palette_auto, true) |> coerce_time_frozen()

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
      lerp_time: 0.0,
      color_mode: color_mode,
      saturation_percent: saturation_percent,
      palette_phase: palette_phase,
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
      buttons: %{},
      panel_interaction_factors: panel_interaction_factors,
      panel_proximities: Map.new(0..(Installation.num_panels() - 1), fn i -> {i, 0.0} end),
      speed: Octopus.Params.Global.speed(),
      display_info: display_info,
      pixel_dirs: pixel_dirs,
      time_frozen: time_frozen,
      show_advanced: Map.get(config, :show_advanced, false) |> coerce_time_frozen(),
      yaw_angle: 0.0,
      roll_angle: 0.0
    }

    state =
      state
      |> put_auto_fields(config)
      |> init_auto_wanderers()

    {:ok, state}
  end

  def handle_config(config, %State{} = state) do
    state = apply_scene_fields(state, config)
    state = if state.time_frozen, do: push_frame(state), else: state
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
    program_source = Map.get(config, :program, state.source)

    program =
      case Program.parse(program_source) do
        {:ok, program} -> program
        _ -> state.program
      end

    color_interval = Map.get(config, :color_interval, state.color_interval)
    color_mode = Map.get(config, :color_mode, state.color_mode)
    saturation_percent = Map.get(config, :saturation_percent, state.saturation_percent || 70)
    palette_phase = coerce_palette_phase(Map.get(config, :palette_phase, state.palette_phase || 0.0))
    palette_auto =
      Map.get(config, :palette_auto, state.palette_auto != false) |> coerce_time_frozen()

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
        palette_phase: palette_phase,
        color_interval: color_interval,
        palette_auto: palette_auto,
        show_advanced:
          Map.get(config, :show_advanced, state.show_advanced || false) |> coerce_time_frozen()
    }

    state = state |> put_auto_fields(config) |> sync_auto_wanderers(old_autos)

    state =
      if color_mode in [:random, :white] do
        apply_palette_colors(state)
      else
        state
      end

    apply_time_frozen(state, config)
  end

  defp apply_time_frozen(%State{} = state, config) do
    new_frozen = Map.get(config, :time_frozen, state.time_frozen || false) |> coerce_time_frozen()
    %State{state | time_frozen: new_frozen}
  end

  defp coerce_config(config) when is_map(config) do
    config
    |> migrate_legacy_config()
    |> Map.new(fn
      {:color_mode, value} -> {:color_mode, coerce_color_mode(value)}
      {:saturation_percent, value} -> {:saturation_percent, coerce_saturation_percent(value)}
      {:palette_phase, value} -> {:palette_phase, coerce_palette_phase(value)}
      {:time_direction, value} -> {:time_direction, coerce_time_direction(value)}
      {:time_frozen, value} -> {:time_frozen, coerce_time_frozen(value)}
      {:palette_auto, value} -> {:palette_auto, coerce_time_frozen(value)}
      {:tilt_mode, value} -> {:tilt_mode, Octopus.Sway.normalize_mode(value)}
      {key, value} -> {key, value}
    end)
  end

  @doc false
  def migrate_legacy_config(config) when is_map(config) do
    config = normalize_config_keys(config)

    migrated =
      config
      |> maybe_migrate_sway()
      |> maybe_migrate_rotate()
      |> maybe_migrate_translate()
      |> maybe_migrate_zoom()
      |> maybe_migrate_elev_drift()
      |> maybe_migrate_trans_auto()
      |> maybe_migrate_auto_tempos()
      |> strip_removed_zoom_keys()
      |> Map.drop(@removed_elev_keys ++ @removed_tx_ty_keys ++ @removed_tempo_keys)

    Map.merge(Map.take(@default_scene, @sphere_scene_keys), migrated)
    |> Map.drop(@removed_elev_keys ++ @removed_zoom_keys ++ @removed_tx_ty_keys ++ @removed_tempo_keys)
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

  defp strip_removed_zoom_keys(config) do
    dropped =
      @removed_zoom_keys
      |> Enum.filter(fn k ->
        v = Map.get(config, k)
        is_number(v) and v != 0
      end)

    if dropped != [] do
      Logger.info(
        "PixelFun: dropping legacy zoom motion #{inspect(Map.take(config, dropped))} from preset config"
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

  defp coerce_time_frozen(value) when value in [true, false], do: value
  defp coerce_time_frozen("true"), do: true
  defp coerce_time_frozen("false"), do: false
  defp coerce_time_frozen(1), do: true
  defp coerce_time_frozen(0), do: false
  defp coerce_time_frozen(_), do: false

  defp time_sign(:backward), do: -1
  defp time_sign(_), do: 1

  defp effective_seconds(%State{} = state), do: state.seconds * time_sign(state.time_direction)

  defp apply_scene_by_id(%State{} = state, scene_id) do
    mod = scene_presets()

    case apply(mod, :get, [scene_id]) do
      nil -> state
      preset -> apply_scene_fields(state, apply(mod, :to_config, [preset]))
    end
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

  defp scene_presets, do: String.to_existing_atom("Elixir.Octopus.Apps.PixelFun.ScenePresets")

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
    state =
      if state.time_frozen do
        state
      else
        state
        |> advance_palette_phase()
        |> advance_tick_state()
      end

    {:noreply, push_frame(state)}
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

    state = %State{
      state
      | seconds: seconds,
        panel_interaction_factors: panel_interaction_factors
    }

    state
    |> step_auto_wanderers()
    |> accumulate_orientation(dt_signed)
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
    dt_yaw = if state.trans_auto, do: abs(dt_signed), else: dt_signed
    dt_roll = if state.rot_auto, do: abs(dt_signed), else: dt_signed

    {yaw, roll} =
      accumulate_orientation_angles(
        state.yaw_angle || 0.0,
        state.roll_angle || 0.0,
        eff.orbit_rate,
        eff.roll_rate,
        dt_yaw,
        dt_roll
      )

    %State{state | yaw_angle: yaw, roll_angle: roll}
  end

  defp step_auto_wanderers(%State{} = state) do
    now = state.seconds

    wanderers =
      Enum.reduce(@auto_channels, state.auto_wanderers || %{}, fn ch, acc ->
        if Map.get(state, :"#{ch}_auto") do
          interval = Map.get(state, :"#{ch}_auto_interval") || @auto_defaults[:"#{ch}_auto_interval"]
          w = Map.get(acc, ch) || new_channel_wanderer(state, ch)
          {_v, next} = step_channel_wanderer(w, now, state, ch, interval)
          Map.put(acc, ch, next)
        else
          Map.delete(acc, ch)
        end
      end)

    %State{state | auto_wanderers: wanderers}
  end

  defp new_channel_wanderer(%State{} = state, :trans) do
    Wander.new({state.orbit_rate || 0.0, state.elev_base || 0.0})
  end

  defp new_channel_wanderer(%State{} = state, ch) do
    Wander.new(Map.get(state, @channel_base_key[ch]) || 0.0)
  end

  defp step_channel_wanderer(w, now, state, :trans, interval) do
    ox = state.orbit_rate || 0.0
    ey = state.elev_base || 0.0
    rx = Map.get(state, :trans_auto_range_x) || @auto_defaults.trans_auto_range_x
    ry = Map.get(state, :trans_auto_range_y) || @auto_defaults.trans_auto_range_y
    {lox, hix} = @channel_bounds.trans_x
    {loy, hiy} = @channel_bounds.trans_y

    Wander.step(w, now, %{
      mins: {max(ox - rx, lox), max(ey - ry, loy)},
      maxs: {min(ox + rx, hix), min(ey + ry, hiy)},
      interval: interval
    })
  end

  defp step_channel_wanderer(w, now, state, ch, interval) do
    base = Map.get(state, @channel_base_key[ch]) || 0.0
    range = Map.get(state, :"#{ch}_auto_range") || @auto_defaults[:"#{ch}_auto_range"]
    {lo, hi} = @channel_bounds[ch]
    min_v = max(base - range, lo)
    max_v = min(base + range, hi)
    Wander.step(w, now, %{min: min_v, max: max_v, interval: interval})
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
    # Deterministic motion (tilt) uses signed time; auto wanderers use state.seconds.
    seconds = effective_seconds(state)
    transform_params = build_transform_params(state, seconds)

    canvas_mode = if state.color_mode == :white, do: :grayscale, else: :rgb
    canvas = Canvas.new(display_info.width, display_info.height, canvas_mode)
    saturation_percent = state.saturation_percent || 70
    pattern_speed = state.pattern_speed || 1.0

    lerp_fn = fn a, b, v ->
      interpolate_colors_with_black(a, b, v, saturation_percent)
    end

    panels = state.pixel_dirs || precompute_pixel_dirs()

    panels
    |> Enum.with_index()
    |> Enum.reduce(canvas, fn {panel, index}, canvas ->
      proximity = Map.get(state.panel_proximities, index, 0.0)
      hue_shift = proximity * 180 * 5
      interaction_factor = Map.get(state.panel_interaction_factors, index, 0.0)

      # pattern_speed scales formula time before time_sign; interaction kick unscaled.
      pixel_time =
        (state.seconds * pattern_speed + interaction_factor * 5) * time_sign(state.time_direction)

      audio = state.audio_input

      Enum.reduce(Enum.with_index(panel), canvas, fn {{x, y, d}, i}, canvas ->
        {x_scaled, y_scaled, {nx, ny, nz}} = sample_pixel(d, x, y, transform_params)

        pixel =
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
              |> white_pixel_value(color_a, color_b)

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

              rainbow_pixel_color(x_scaled, y_scaled, value, hue_shift, saturation_percent)

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

        Canvas.put_pixel(canvas, {x, y}, pixel)
      end)
    end)
  end

  defp precompute_pixel_dirs do
    w = Installation.width()
    h = Installation.height()

    Installation.virtual_pixel_positions_per_panel()
    |> Enum.map(fn panel ->
      Enum.map(panel, fn {x, y} -> {x, y, Sphere.direction(x, y, w, h)} end)
    end)
  end

  defp build_transform_params(%State{} = state, seconds) do
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
    zoom_base = eff.zoom_base
    sigma = zoom_base

    yaw_angle = state.yaw_angle || orbit_rate * seconds
    roll_angle = state.roll_angle || roll_rate * seconds

    neutral? =
      orbit_rate == 0.0 and roll_rate == 0.0 and tilt_scale == 0.0 and elev_base == 0.0 and
        sigma == 0.0 and not any_auto?(state) and yaw_angle == 0.0 and roll_angle == 0.0

    if neutral? do
      %{neutral?: true, center_x: cx, center_y: cy, alpha: alpha}
    else
      tilt_amp_rad = tilt_scale * alpha
      roll_pivot_phi = panel_to_phi(state.roll_pivot || 0, w, alpha)
      zoom_pivot_phi = panel_to_phi(state.zoom_pivot || 0, w, alpha)

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
        sigma: sigma,
        mobius_basis: Sphere.mobius_basis(zoom_pivot_phi),
        elev_rad: Sphere.elev_offset(elev_base, alpha),
        alpha: alpha,
        center_x: cx,
        center_y: cy
      }
    end
  end

  defp panel_to_phi(panel, w, alpha) do
    n = max(Installation.num_panels(), 1)
    panel = panel |> trunc() |> max(0) |> min(n - 1)
    stride = Installation.panel_width() + Installation.panel_gap()
    cx = w / 2 - 0.5
    center_x = panel * stride + Installation.panel_width() / 2 - 0.5
    (center_x - cx) * alpha
  end

  defp sample_pixel(d, x, y, %{neutral?: true} = params) do
    Sphere.sample(d, Map.put(params, :x, x) |> Map.put(:y, y))
  end

  defp sample_pixel(d, _x, _y, params), do: Sphere.sample(d, params)

  @doc false
  def transform_pixel_coords(x, y, params) do
    w = Installation.width()
    h = Installation.height()
    d = Map.get(params, :direction) || Sphere.direction(x, y, w, h)

    transform_params =
      case params do
        %{neutral?: _} = p ->
          p

        _ ->
          motion =
            default_motion_state()
            |> Map.merge(Map.take(params, Map.keys(default_motion_state())))

          state_like = struct(State, motion)
          build_transform_params(state_like, Map.get(params, :seconds, 0.0))
      end

    {xs, ys, _d} = sample_pixel(d, x, y, Map.merge(transform_params, %{x: x, y: y}))
    {xs, ys}
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
      zoom_base: 0.0,
      zoom_pivot: 0,
      pattern_speed: 1.0,
      trans_auto: false,
      rot_auto: false,
      zoom_auto: false,
      sway_auto: false,
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
          coerce_time_frozen(Map.get(config, auto_key, Map.get(acc, auto_key) || false))
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
    wanderers =
      Enum.reduce(@auto_channels, state.auto_wanderers || %{}, fn ch, acc ->
        was = Map.get(old_flags, ch, false)
        now? = Map.get(state, :"#{ch}_auto") || false

        cond do
          now? and not was ->
            Map.put(acc, ch, new_channel_wanderer(state, ch))

          not now? and was ->
            Map.delete(acc, ch)

          true ->
            acc
        end
      end)

    %State{state | auto_wanderers: wanderers}
  end

  defp any_auto?(%State{} = state) do
    Enum.any?(@auto_channels, &(Map.get(state, :"#{&1}_auto") || false))
  end

  defp effective_transform_values(%State{} = state) do
    orbit = state.orbit_rate || 0.0
    elev = state.elev_base || 0.0
    roll = state.roll_rate || 0.0
    zoom = state.zoom_base || 0.0
    sway = state.tilt_scale || 0.0

    {orbit, elev} =
      if state.trans_auto do
        case state.auto_wanderers do
          %{trans: %Wander{value: {ox, ey}}} -> {ox, ey}
          _ -> {orbit, elev}
        end
      else
        {orbit, elev}
      end

    wander_val = fn ch, base ->
      if Map.get(state, :"#{ch}_auto") do
        case state.auto_wanderers do
          %{^ch => %Wander{value: {v}}} -> v
          _ -> base
        end
      else
        base
      end
    end

    %{
      orbit_rate: orbit,
      elev_base: elev,
      roll_rate: wander_val.(:rot, roll),
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

  defp white_pixel_value(value, %Chameleon.HSV{v: level_a}, %Chameleon.HSV{v: level_b}) do
    level =
      cond do
        value > 0 -> level_a * value
        value < 0 -> level_b * -value
        true -> 0
      end

    level
    |> Kernel.*(param(:value_percent, 100) / 100.0)
    |> Kernel.*(255 / 100.0)
    |> round()
    |> max(0)
    |> min(255)
  end

  defp rainbow_pixel_color(_x, _y, value, _hue_shift, _saturation_percent) when value == 0.0,
    do: {0, 0, 0}

  defp rainbow_pixel_color(x, y, value, hue_shift, saturation_percent) do
    hue = rainbow_hue(x, y, hue_shift)

    saturation = saturation_percent |> max(0) |> min(100)
    brightness = trunc(param(:value_percent, 100) * abs(value)) |> max(0) |> min(100)

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

  defp interpolate_colors_with_black(%Chameleon.HSV{} = a, %Chameleon.HSV{} = b, value, saturation_percent) do
    saturation = saturation_percent |> max(0) |> min(100)

    hsv =
      cond do
        value > 0 ->
          %Chameleon.HSV{
            a
            | s: saturation,
              v: trunc(param(:value_percent, 100) * value) |> max(0) |> min(100)
          }

        value < 0 ->
          %Chameleon.HSV{
            b
            | s: saturation,
              v: trunc(param(:value_percent, 100) * -value) |> max(0) |> min(100)
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

  defp advance_palette_phase(%State{} = state) do
    if state.color_mode in [:random, :white] and state.palette_auto != false do
      period = max(state.color_interval || 5.0, 0.1)
      dt = (1 / @fps) * param(:time_scale, 1.0) * state.speed
      phase = wrap_unit((state.palette_phase || 0.0) + dt / period)

      apply_palette_colors(%State{state | palette_phase: phase})
    else
      state
    end
  end

  defp apply_palette_colors(%State{color_mode: mode} = state) when mode in [:random, :white] do
    palette =
      palette_from_phase(state.palette_phase || 0.0, mode, state.saturation_percent || 70)

    %State{state | colors: palette, last_colors: palette, target_colors: palette}
  end

  defp apply_palette_colors(%State{} = state), do: state

  defp wrap_unit(x) when is_number(x), do: x - :math.floor(x)
  defp wrap_unit(_), do: 0.0

  defp coerce_palette_phase(value) when is_number(value), do: wrap_unit(value)

  defp coerce_palette_phase(value) when is_binary(value) do
    case Float.parse(value) do
      {n, _} -> wrap_unit(n)
      :error -> 0.0
    end
  end

  defp coerce_palette_phase(_), do: 0.0

  @doc false
  def palette_from_phase(phase, color_mode, saturation_percent \\ 70)

  def palette_from_phase(phase, :white, _saturation_percent) do
    t = wrap_unit(phase)
    # Continuous brightness pair with guaranteed gap (≥ @min_white_level_gap).
    center = 50.0 + 15.0 * :math.sin(t * :math.pi() * 2)
    half = @min_white_level_gap / 2 + 10.0 + 8.0 * :math.cos(t * :math.pi() * 2)
    a = trunc(max(@min_white_level, min(100, center - half)))
    b = trunc(max(@min_white_level, min(100, center + half)))

    {a, b} =
      if abs(a - b) < @min_white_level_gap do
        if a <= b do
          {a, min(100, a + @min_white_level_gap)}
        else
          {min(100, b + @min_white_level_gap), b}
        end
      else
        {a, b}
      end

    {%Chameleon.HSV{h: 0, s: 0, v: a}, %Chameleon.HSV{h: 0, s: 0, v: b}}
  end

  def palette_from_phase(phase, _color_mode, saturation_percent) do
    t = wrap_unit(phase)
    hue_a = trunc(t * 360) |> rem(360)
    hue_b = rem(hue_a + 180, 360)
    sat = saturation_percent |> max(0) |> min(100)
    {Chameleon.HSV.new(hue_a, sat, 100), Chameleon.HSV.new(hue_b, sat, 100)}
  end
end
