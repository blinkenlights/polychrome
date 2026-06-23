defmodule Octopus.Apps.Collective do
  @moduledoc """
  Collective — animations driven by the crowd's movement and position data.

  Consumes the radar PubSub feed (`Octopus.Radar.subscribe/0`,
  `{:radar_frame, device_id, %Octopus.Radar.Frame{}}`). In dev that feed is
  produced by `Octopus.Apps.Collective.MockRadar`, which also drives the people
  shown in the 3D sim — so the sim and these animations react to the exact same
  crowd. When Tim's mock server or real hardware broadcasts on the same topic,
  this app keeps working unchanged.

  The app owns a fixed-rate render tick (decoupled from the radar frame rate) and
  hands the latest people to the selected animation (`Octopus.Apps.Collective.Animation`).

  The `Mock Movement` slider proxies to `MockRadar` (global speed multiplier) and
  only has an effect while the dev mock feed is running; against real data it is a
  no-op. The mock population is autonomous (1-20 people), so there is no count slider.
  """

  use Octopus.App, category: :animation

  alias Octopus.Canvas
  alias Octopus.Radar
  alias Octopus.Radar.Frame
  alias Octopus.Apps.Collective.MockRadar
  alias Octopus.Apps.Collective.Animations

  @fps 30
  @frame_ms trunc(1000 / @fps)

  # Maps the :select config value to the animation module.
  @animations %{storm: Animations.Storm}

  def name, do: "Collective"

  def app_init(config) do
    Octopus.App.configure_display(layout: :adjacent_panels)
    display_info = Octopus.App.get_display_info()

    Radar.subscribe()

    movement = Map.get(config, :movement, 1.0)
    sensitivity = Map.get(config, :sensitivity, 1.0)
    background = Map.get(config, :background, :deep_dark)
    animation = Map.get(config, :animation, :storm)
    anim_mod = Map.fetch!(@animations, animation)

    # Seed the dev mock feed with this app's config (no-op without the mock).
    MockRadar.set_movement(movement)

    :timer.send_interval(@frame_ms, :tick)

    state = %{
      canvas: Canvas.new(display_info.width, display_info.height),
      display_info: display_info,
      people: [],
      movement: movement,
      sensitivity: sensitivity,
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
      movement: state.movement,
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

  def config_schema do
    %{
      animation:
        {"Animation", :select, %{default: 0, options: [{"Bewegungs-Sturm", :storm}]}},
      background:
        {"Background", :select,
         %{default: 0, options: [{"Deep Dark", :deep_dark}, {"Still Stars", :still_stars}]}},
      movement: {"Mock Movement", :float, %{min: 0.0, max: 2.0, default: 1.0}},
      sensitivity: {"Storm Sensitivity", :float, %{min: 0.2, max: 3.0, default: 1.0}}
    }
  end

  def get_config(state) do
    %{
      animation: state.animation,
      background: state.background,
      movement: state.movement,
      sensitivity: state.sensitivity
    }
  end

  def handle_config(config, state) do
    animation = Map.get(config, :animation, state.animation)
    movement = Map.get(config, :movement, state.movement)

    {anim_mod, anim_state} =
      if animation != state.animation do
        mod = Map.fetch!(@animations, animation)
        {mod, mod.init(state.display_info)}
      else
        {state.anim_mod, state.anim_state}
      end

    if movement != state.movement, do: MockRadar.set_movement(movement)

    {:noreply,
     %{
       state
       | animation: animation,
         anim_mod: anim_mod,
         anim_state: anim_state,
         movement: movement,
         background: Map.get(config, :background, state.background),
         sensitivity: Map.get(config, :sensitivity, state.sensitivity)
     }}
  end

  defp track_to_person(track) do
    %{id: track.id, x: track.x, y: track.y, vx: track.vx, vy: track.vy}
  end

  defp now_ms, do: :erlang.monotonic_time(:millisecond)
end
