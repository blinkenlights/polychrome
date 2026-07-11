defmodule Octopus.Apps.Sand do
  use Octopus.App, category: :interactive

  @mode_presets Module.concat(["Octopus", "AppModePresets"])

  alias Octopus.Installation
  alias Octopus.Canvas
  alias Octopus.Apps.Sand.Sim
  alias Octopus.Events.Event.Input
  alias Octopus.Particles

  @fps 30
  @default_supersample 4

  defmodule State do
    defstruct [
      :sim,
      :particles,
      :panels,
      :display_info,
      :spawn_rate,
      :button_force,
      :auto_drain,
      :color_mode,
      :supersample,
      :gravity
    ]
  end

  defmodule Panel do
    defstruct [:index]
  end

  def name, do: "🏖️ Sand"

  def list_modes do
    apply(@mode_presets, :list_modes, [__MODULE__])
  end

  def mode_config(mode_id) do
    slug = apply(@mode_presets, :mode_slug, [mode_id])
    defaults = legacy_mode_config(slug)

    stored = apply(@mode_presets, :config_for, [__MODULE__, mode_id]) || %{}

    defaults
    |> Map.merge(stored)
    |> normalize_mode_config()
  end

  def normalize_mode_config(config), do: coerce_config_atoms(config)

  def builtin_presets do
    [
      %{
        slug: "sand",
        name: "Sand",
        accent_color: "#E8A838",
        config: legacy_mode_config("sand")
      }
    ]
  end

  def legacy_mode_config("sand") do
    s = @default_supersample

    %{
      spawn_rate: 0.25,
      button_force: 40,
      auto_drain: true,
      color_mode: :rainbow,
      supersample: s,
      gravity: Sim.default_gravity(s)
    }
  end

  def legacy_mode_config(_), do: %{}

  def mode_tweakables(mode_id) do
    mode_tweakables_for(apply(@mode_presets, :mode_slug, [mode_id]))
  end

  def mode_tweakables_for("sand") do
    s = @default_supersample

    [
      %{
        key: :spawn_rate,
        label: "Spawn rate",
        type: :slider,
        min: 0.05,
        max: 0.8,
        step: 0.05,
        default: 0.25
      },
      %{
        key: :button_force,
        label: "Button blast",
        type: :slider,
        min: 10,
        max: 80,
        step: 1,
        default: 40
      },
      %{
        key: :auto_drain,
        label: "Auto clear when full",
        type: :toggle,
        default: true
      },
      %{
        key: :color_mode,
        label: "Colors",
        type: :choice,
        default: :rainbow,
        options: [
          {:rainbow, "Rainbow"},
          {:warm, "Warm"},
          {:cool, "Cool"},
          {:mono, "Mono"}
        ]
      },
      %{
        key: :supersample,
        label: "Supersample",
        type: :slider,
        min: 1,
        max: 6,
        step: 1,
        default: @default_supersample
      },
      %{
        key: :gravity,
        label: "Gravity",
        type: :slider,
        min: 0.0,
        max: 3.0,
        step: 0.05,
        default: Sim.default_gravity(s)
      }
    ]
  end

  def mode_tweakables_for(_), do: []

  def now_playing_meta(config) do
    spawn_rate = Map.get(config, :spawn_rate, 0.25)
    button_force = Map.get(config, :button_force, 40)
    auto_drain = Map.get(config, :auto_drain, true)
    color_mode = Map.get(config, :color_mode, :rainbow)
    supersample = Map.get(config, :supersample, @default_supersample)
    gravity = Map.get(config, :gravity, Sim.default_gravity(supersample))

    [
      "spawn #{round(spawn_rate * 100)}%",
      "blast #{button_force}",
      if(auto_drain, do: "auto-drain on", else: "auto-drain off"),
      to_string(color_mode),
      "S=#{supersample} grav=#{Float.round(gravity, 2)}",
      "Press buttons to explode"
    ]
  end

  def config_schema do
    s = @default_supersample

    %{
      spawn_rate: {"Spawn Rate", :float, %{default: 0.25, min: 0.05, max: 0.8, step: 0.05}},
      button_force: {"Button Blast", :integer, %{default: 40, min: 10, max: 80}},
      auto_drain: {"Auto Clear When Full", :boolean, %{default: true}},
      color_mode: {"Colors", :atom, %{default: :rainbow}},
      supersample: {"Supersample", :integer, %{default: s, min: 1, max: 6}},
      gravity: {"Gravity", :float, %{default: Sim.default_gravity(s), min: 0.0, max: 3.0, step: 0.05}}
    }
  end

  def compatible?() do
    buttons = Installation.num_buttons()
    panels = Installation.num_panels()

    panels > 0 and (buttons == 0 or buttons == panels)
  end

  def app_init(config) do
    configure_display(layout: :gapped_panels_wrapped)
    Octopus.App.subscribe_to_button_events()

    display_info = Octopus.App.get_display_info()

    panels =
      for i <- 0..(display_info.num_panels - 1), into: %{} do
        {i, %Panel{index: i}}
      end

    :timer.send_interval(trunc(1000 / @fps), self(), :tick)
    send(self(), :tick)

    state =
      %State{
        panels: panels,
        display_info: display_info,
        particles:
          Particles.new(display_info.width, display_info.height, 0, 0, [{255, 255, 255}])
      }

    {:ok, apply_config(state, config)}
  end

  def handle_config(config, %State{} = state) do
    {:noreply, apply_config(state, config)}
  end

  def get_config(%State{} = state) do
    %{
      spawn_rate: state.spawn_rate,
      button_force: state.button_force,
      auto_drain: state.auto_drain,
      color_mode: state.color_mode,
      supersample: state.supersample,
      gravity: state.gravity
    }
  end

  def handle_info(:tick, %State{} = state) do
    config = get_config(state)

    state =
      state
      |> spawn_all_panels(config)
      |> maybe_auto_drain(config)

    sim = Sim.step(state.sim)
    particles = Particles.update(state.particles, 1 / @fps)

    canvas =
      state
      |> Map.put(:sim, sim)
      |> Map.put(:particles, particles)
      |> draw()

    update_display(canvas)

    {:noreply, %{state | sim: sim, particles: particles}}
  end

  def handle_event(%Input{type: :button, action: :press} = input, %State{} = state) do
    index = input.button - 1
    config = get_config(state)

    force = Map.get(config, :button_force, 40)
    {sim, particles} =
      explode_panel(
        state.sim,
        state.particles,
        state.display_info,
        index,
        force * 0.75,
        force * 1.25
      )

    {:noreply, %{state | sim: sim, particles: particles}}
  end

  def handle_event(_event, state) do
    {:noreply, state}
  end

  defp spawn_all_panels(%State{} = state, config) do
    sim =
      Enum.reduce(state.panels, state.sim, fn {_i, panel}, sim ->
        maybe_spawn_sand(sim, panel, state.display_info, config)
      end)

    %{state | sim: sim}
  end

  defp maybe_spawn_sand(sim, _panel, _display_info, %{spawn_rate: spawn_rate})
       when spawn_rate <= 0,
       do: sim

  defp maybe_spawn_sand(sim, %Panel{} = panel, display_info, config) do
    spawn_rate = Map.get(config, :spawn_rate, 0.25)

    if :rand.uniform() > 1 - spawn_rate do
      {start_x, end_x} = display_info.panel_range.(panel.index, :x)
      color = random_color(panel, config)
      spawn_grains(sim, start_x, end_x, color)
    else
      sim
    end
  end

  defp spawn_grains(sim, panel_start_x, panel_end_x, color) do
    drops = Enum.random(2..4)

    Enum.reduce(1..drops, sim, fn _, sim ->
      sim_spawn_coords(sim, panel_start_x, panel_end_x)
      |> Enum.reduce(sim, fn {x, y}, sim ->
        Sim.put_cell(sim, {x, y}, Sim.sand(color))
      end)
    end)
  end

  defp sim_spawn_coords(%Sim{supersample: s}, panel_start_x, panel_end_x) do
    sim_start = panel_start_x * s
    sim_end = panel_end_x * s + (s - 1)
    sim_x = Enum.random(sim_start..sim_end)
    spawn_y = Enum.random(-s..-1)

    if s >= 3 do
      cluster_x = min(sim_x, sim_end - 1)

      for dy <- 0..1, dx <- 0..1, do: {cluster_x + dx, spawn_y + dy}
    else
      [{sim_x, spawn_y}]
    end
  end

  defp maybe_auto_drain(%State{} = state, %{auto_drain: false}), do: state

  defp maybe_auto_drain(%State{} = state, _config) do
    full? =
      Enum.any?(state.panels, fn {_i, panel} ->
        panel_full?(state.sim, state.display_info, panel.index)
      end)

    if full? && :rand.uniform() > 0.75 do
      panel_index = Enum.random(Map.keys(state.panels))

      {sim, particles} =
        explode_panel(state.sim, state.particles, state.display_info, panel_index, -5, 0)

      %{state | sim: sim, particles: particles}
    else
      state
    end
  end

  defp panel_full?(%Sim{} = sim, display_info, panel_index) do
    {start_x, end_x} = display_info.panel_range.(panel_index, :x)
    panel_height = display_info.panel_height

    coords =
      for y <- 0..(panel_height - 1), x <- start_x..end_x do
        {x, y}
      end

    Enum.all?(coords, fn coord -> not led_cell_empty?(sim, coord) end)
  end

  defp led_cell_empty?(%Sim{} = sim, {led_x, led_y}) do
    s = sim.supersample

    Enum.all?(0..(s - 1), fn dy ->
      Enum.all?(0..(s - 1), fn dx ->
        Sim.cell_empty?(sim, {led_x * s + dx, led_y * s + dy})
      end)
    end)
  end

  defp draw(%State{} = state) do
    canvas = Sim.draw(state.sim, Canvas.new(state.display_info.width, state.display_info.height))

    particle_canvas = Particles.draw(state.particles, Canvas.new(state.display_info.width, state.display_info.height))

    Enum.reduce(particle_canvas.pixels, canvas, fn {{x, y}, color}, canvas ->
      Canvas.put_pixel(canvas, {x, y}, color)
    end)
  end

  defp explode_panel(sim, particles, display_info, panel_index, min_force, max_force) do
    {start_x, end_x} = display_info.panel_range.(panel_index, :x)
    s = sim.supersample

    {sim, particles} =
      Enum.reduce(sim.particles, {sim, particles}, fn {{x, y}, {:sand, color, _vy}}, {sim, particles} ->
        led_x = div(x, s)
        led_y = div(y, s)

        if led_x >= start_x and led_x <= end_x do
          particles =
            Particles.spawn(particles, {led_x, led_y}, 1,
              angle: :math.pi() * 1.5,
              spread: 0.15,
              colors: color,
              min_speed: min_force,
              max_speed: max_force
            )

          {Sim.remove_cell(sim, {x, y}), particles}
        else
          {sim, particles}
        end
      end)

    {sim, particles}
  end

  defp random_color(%Panel{index: index}, config) do
    color_mode = Map.get(config, :color_mode, :rainbow)
    num_panels = max(Installation.num_panels(), 1)

    hue =
      case color_mode do
        :warm -> :rand.uniform() * 40 + 20
        :cool -> :rand.uniform() * 60 + 180
        :mono -> 0
        _ -> 360 * index / num_panels
      end

    hue = rem(trunc(hue), 360)
    saturation = :rand.uniform() * 25 + 60
    lightness = :rand.uniform() * 25 + 45
    hsl = Chameleon.HSL.new(trunc(hue), trunc(saturation), trunc(lightness))
    %Chameleon.RGB{r: r, g: g, b: b} = Chameleon.convert(hsl, Chameleon.RGB)
    {r, g, b}
  end

  defp apply_config(%State{} = state, config) do
    config = coerce_config_atoms(config)
    defaults = legacy_mode_config("sand")

    supersample =
      Map.get(config, :supersample, Map.get(state, :supersample) || defaults.supersample)

    gravity =
      Map.get(config, :gravity, Map.get(state, :gravity) || Sim.default_gravity(supersample))

    new_state = %State{
      state
      | spawn_rate: Map.get(config, :spawn_rate, Map.get(state, :spawn_rate) || defaults.spawn_rate),
        button_force:
          Map.get(config, :button_force, Map.get(state, :button_force) || defaults.button_force),
        auto_drain: Map.get(config, :auto_drain, Map.get(state, :auto_drain) || defaults.auto_drain),
        color_mode: Map.get(config, :color_mode, Map.get(state, :color_mode) || defaults.color_mode),
        supersample: supersample,
        gravity: gravity
    }

    sim =
      cond do
        is_nil(state.display_info) ->
          state.sim

        is_nil(state.sim) ->
          build_sim(new_state)

        state.supersample != supersample ->
          build_sim(new_state)

        true ->
          Sim.with_gravity(state.sim, gravity)
      end

    %{new_state | sim: sim}
  end

  defp build_sim(%State{display_info: display_info, supersample: s, gravity: gravity}) do
    panel_led_ranges =
      for i <- 0..(display_info.num_panels - 1) do
        display_info.panel_range.(i, :x)
      end

    Sim.new(display_info.width, display_info.height,
      supersample: s,
      gravity: gravity,
      panel_led_ranges: panel_led_ranges
    )
  end

  defp coerce_config_atoms(config) when is_map(config) do
    Map.new(config, fn
      {:color_mode, value} -> {:color_mode, coerce_color_mode(value)}
      {key, value} -> {key, value}
    end)
  end

  defp coerce_color_mode(value) when is_atom(value), do: value

  defp coerce_color_mode(value) when is_binary(value) do
    case value do
      "warm" -> :warm
      "cool" -> :cool
      "mono" -> :mono
      _ -> :rainbow
    end
  end

  defp coerce_color_mode(_), do: :rainbow
end
