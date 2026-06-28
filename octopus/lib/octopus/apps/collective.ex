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
  alias Octopus.Apps.Collective.Animations

  @fps 30
  @frame_ms trunc(1000 / @fps)

  # Maps the :select config value to the animation module.
  @animations %{storm: Animations.Storm, breath: Animations.Breath}

  def name, do: "Collective"

  def app_init(config) do
    Octopus.App.configure_display(layout: :adjacent_panels)
    display_info = Octopus.App.get_display_info()

    Radar.subscribe()

    sensitivity = Map.get(config, :sensitivity, 1.0)
    breath_liveliness = Map.get(config, :breath_liveliness, 0.25)
    breath_palette = Map.get(config, :breath_palette, :ocean)
    breath_hue_shift = Map.get(config, :breath_hue_shift, 0.0)
    breath_layout = Map.get(config, :breath_layout, :wave)
    background = Map.get(config, :background, :deep_dark)
    animation = Map.get(config, :animation, :storm)
    anim_mod = Map.fetch!(@animations, animation)

    :timer.send_interval(@frame_ms, :tick)

    state = %{
      canvas: Canvas.new(display_info.width, display_info.height),
      display_info: display_info,
      people: [],
      sensitivity: sensitivity,
      breath_liveliness: breath_liveliness,
      breath_palette: breath_palette,
      breath_hue_shift: breath_hue_shift,
      breath_layout: breath_layout,
      background: background,
      animation: animation,
      anim_mod: anim_mod,
      anim_state: anim_mod.init(display_info),
      last_update: now_ms()
    }

    {:ok, state}
  end

  def handle_info({:radar_frame, _device_id, %Frame{} = frame}, state) do
    people = Enum.map(frame.tracks, &track_to_person/1)
    {:noreply, %{state | people: people}}
  end

  def handle_info(:tick, state) do
    now = now_ms()
    dt = max(now - state.last_update, 0) / 1000.0

    ctx = %{
      dt: dt,
      sensitivity: state.sensitivity,
      breath_liveliness: state.breath_liveliness,
      breath_palette: state.breath_palette,
      breath_hue_shift: state.breath_hue_shift,
      breath_layout: state.breath_layout,
      background: state.background,
      display_info: state.display_info
    }

    {canvas, anim_state} =
      state.canvas
      |> Canvas.clear()
      |> state.anim_mod.render(state.people, ctx, state.anim_state)

    Octopus.App.update_display(canvas)

    {:noreply, %{state | canvas: canvas, anim_state: anim_state, last_update: now}}
  end

  # Keyword list => the config UI renders in this exact order (Animation first).
  # `visible_when: {:animation, [...]}` hides storm-only options unless Tempest
  # is selected.
  def config_schema do
    [
      animation:
        {"Animation", :select,
         %{default: 0, options: [{"Tempest", :storm}, {"Crowd Breath", :breath}]}},
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
         }}
    ]
  end

  # Field-test cheat sheet: how the selected animation reads the radar feed.
  # Rendered under the config form and refreshed whenever the config changes.
  def config_info(%{animation: :storm}) do
    """
    Tempest — per-person lightning + entry meteors.
    Reads POSITION and VELOCITY. Fast movement → bolts at that column. Someone
    crossing inward into the 18 m-diameter ring (9 m radius, = aframe panel ring)
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

  def config_info(_config), do: nil

  def get_config(state) do
    %{
      animation: state.animation,
      background: state.background,
      sensitivity: state.sensitivity,
      breath_liveliness: state.breath_liveliness,
      breath_palette: state.breath_palette,
      breath_hue_shift: state.breath_hue_shift,
      breath_layout: state.breath_layout
    }
  end

  def handle_config(config, state) do
    animation = Map.get(config, :animation, state.animation)

    {anim_mod, anim_state} =
      if animation != state.animation do
        mod = Map.fetch!(@animations, animation)
        {mod, mod.init(state.display_info)}
      else
        {state.anim_mod, state.anim_state}
      end

    {:noreply,
     %{
       state
       | animation: animation,
         anim_mod: anim_mod,
         anim_state: anim_state,
         background: Map.get(config, :background, state.background),
         sensitivity: Map.get(config, :sensitivity, state.sensitivity),
         breath_liveliness: Map.get(config, :breath_liveliness, state.breath_liveliness),
         breath_palette: Map.get(config, :breath_palette, state.breath_palette),
         breath_hue_shift: Map.get(config, :breath_hue_shift, state.breath_hue_shift),
         breath_layout: Map.get(config, :breath_layout, state.breath_layout)
     }}
  end

  defp track_to_person(track) do
    %{id: track.id, x: track.x, y: track.y, vx: track.vx, vy: track.vy}
  end

  defp now_ms, do: :erlang.monotonic_time(:millisecond)
end
