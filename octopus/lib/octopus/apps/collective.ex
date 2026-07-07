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
  @frame_ms trunc(1000 / @fps)
  @track_stale_ms 1500

  # Maps the :select config value to the animation module.
  @animations %{
    storm: Animations.Storm,
    breath: Animations.Breath,
    dots: Animations.Dots,
    orbital: Animations.Orbital
  }

  def name, do: "Collective"

  def app_init(config) do
    Octopus.App.configure_display(layout: :adjacent_panels)
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
    background = Map.get(config, :background, :deep_dark)
    animation = Map.get(config, :animation, :storm)
    anim_mod = Map.fetch!(@animations, animation)

    :timer.send_interval(@frame_ms, :tick)

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
    now = :erlang.monotonic_time(:millisecond)
    dt = max(now - state.last_update, 0) / 1000.0
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
      background: state.background,
      display_info: state.display_info
    }

    {canvas, anim_state} =
      Canvas.new(state.display_info.width, state.display_info.height)
      |> state.anim_mod.render(people, ctx, state.anim_state)

    Octopus.App.update_display(canvas)

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
             {"Orbital", :orbital}
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

  def config_info(_config), do: nil

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
      orbital_sun_gain: state.orbital_sun_gain
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
         breath_layout: Map.get(config, :breath_layout, state.breath_layout),
         dots_smoothing: Map.get(config, :dots_smoothing, state.dots_smoothing),
         orbital_liveliness: Map.get(config, :orbital_liveliness, state.orbital_liveliness),
         orbital_sun_gain: Map.get(config, :orbital_sun_gain, state.orbital_sun_gain)
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
end
