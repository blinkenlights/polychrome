defmodule Octopus.Apps.Sand do
  use Octopus.App, category: :interactive

  @mode_presets Module.concat(["Octopus", "AppModePresets"])

  alias Octopus.Installation
  alias Octopus.Canvas
  alias Octopus.Apps.Sand.Sim
  alias Octopus.Events.Event.Input
  alias Octopus.Particles

  @fps 30

  defmodule State do
    defstruct [:panels, :spawn_rate, :button_force, :auto_drain, :color_mode]
  end

  def name, do: "🏖️ Sand"

  def list_modes do
    apply(@mode_presets, :list_modes, [__MODULE__])
  end

  def mode_config(mode_id) do
    (apply(@mode_presets, :config_for, [__MODULE__, mode_id]) ||
       legacy_mode_config(apply(@mode_presets, :mode_slug, [mode_id])))
    |> coerce_config_atoms()
  end

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
    %{
      spawn_rate: 0.25,
      button_force: 40,
      auto_drain: true,
      color_mode: :rainbow
    }
  end

  def legacy_mode_config(_), do: %{}

  def mode_tweakables(mode_id) do
    mode_tweakables_for(apply(@mode_presets, :mode_slug, [mode_id]))
  end

  def mode_tweakables_for("sand") do
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
      }
    ]
  end

  def mode_tweakables_for(_), do: []

  def now_playing_meta(config) do
    spawn_rate = Map.get(config, :spawn_rate, 0.25)
    button_force = Map.get(config, :button_force, 40)
    auto_drain = Map.get(config, :auto_drain, true)
    color_mode = Map.get(config, :color_mode, :rainbow)

    [
      "spawn #{round(spawn_rate * 100)}%",
      "blast #{button_force}",
      if(auto_drain, do: "auto-drain on", else: "auto-drain off"),
      to_string(color_mode),
      "Press buttons to explode"
    ]
  end

  def config_schema do
    %{
      spawn_rate: {"Spawn Rate", :float, %{default: 0.25, min: 0.05, max: 0.8, step: 0.05}},
      button_force: {"Button Blast", :integer, %{default: 40, min: 10, max: 80}},
      auto_drain: {"Auto Clear When Full", :boolean, %{default: true}},
      color_mode: {"Colors", :atom, %{default: :rainbow}}
    }
  end

  defmodule Panel do
    defstruct [:index, :sim, :particles]

    def new(index, width, height) do
      %Panel{
        index: index,
        sim: Sim.new(width, height),
        particles: Particles.new(width, height, 0, 0, [{255, 255, 255}])
      }
    end

    def step(%Panel{} = panel, config) do
      panel
      |> maybe_spawn_sand(config)
      |> maybe_drain_particles(config)
      |> update_sim()
    end

    defp maybe_spawn_sand(%Panel{} = panel, config) do
      spawn_rate = Map.get(config, :spawn_rate, 0.25)

      if :rand.uniform() > 1 - spawn_rate do
        x = Enum.random(0..(Installation.panel_width() - 1))
        spawn_pos = {x, -1}

        %Panel{
          panel
          | sim: Sim.put_cell(panel.sim, spawn_pos, {:sand, random_color(panel, config)})
        }
      else
        panel
      end
    end

    defp maybe_drain_particles(%Panel{} = panel, %{auto_drain: false}), do: panel

    defp maybe_drain_particles(%Panel{} = panel, _config) do
      coords =
        for y <- 0..(Installation.panel_height() - 1),
            x <- 0..(Installation.panel_width() - 1),
            do: {x, y}

      if :rand.uniform() > 0.75 &&
           Enum.all?(coords, fn {x, y} ->
             !Sim.cell_empty?(panel.sim, {x, y})
           end) do
        explode(panel, -5, 0)
      else
        panel
      end
    end

    def draw(%Panel{} = panel) do
      sim_canvas = Sim.draw(panel.sim, Canvas.new(panel.sim.width, panel.sim.height))

      particle_canvas =
        panel.particles
        |> Particles.draw(Canvas.new(panel.particles.width, panel.particles.height))

      Enum.reduce(particle_canvas.pixels, sim_canvas, fn {{x, y}, color}, canvas ->
        Canvas.put_pixel(canvas, {x, y}, color)
      end)
    end

    defp update_sim(%Panel{} = panel) do
      %Panel{
        panel
        | sim: Sim.step(panel.sim),
          particles: Particles.update(panel.particles, 1 / 30.0)
      }
    end

    def handle_button_press(%Panel{} = panel, config) do
      force = Map.get(config, :button_force, 40)
      min_force = force * 0.75
      max_force = force * 1.25
      explode(panel, min_force, max_force)
    end

    defp explode(%Panel{} = panel, min_force, max_force) do
      sim = panel.sim
      particles = panel.particles

      particles =
        Enum.reduce(sim.particles, particles, fn {{x, y}, {:sand, color}}, particles ->
          Particles.spawn(particles, {x, y}, 1,
            angle: :math.pi() * 1.5,
            spread: 0.15,
            colors: color,
            min_speed: min_force,
            max_speed: max_force
          )
        end)

      sim = Sim.clear(sim)

      %Panel{panel | sim: sim, particles: particles}
    end

    def random_color(%Panel{index: index}, config) do
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
  end

  def compatible?() do
    Installation.num_buttons() == Installation.num_panels()
  end

  def app_init(config) do
    configure_display(layout: :adjacent_panels)
    Octopus.App.subscribe_to_button_events()

    panels =
      for i <- 0..(Installation.num_panels() - 1), into: %{} do
        {i, Panel.new(i, Installation.panel_width(), Installation.panel_height())}
      end

    :timer.send_interval(trunc(1000 / @fps), self(), :tick)
    send(self(), :tick)

    {:ok, apply_config(%State{panels: panels}, config)}
  end

  def handle_config(config, %State{} = state) do
    {:noreply, apply_config(state, config)}
  end

  def get_config(%State{} = state) do
    %{
      spawn_rate: state.spawn_rate,
      button_force: state.button_force,
      auto_drain: state.auto_drain,
      color_mode: state.color_mode
    }
  end

  def handle_info(:tick, %State{} = state) do
    config = get_config(state)

    panels =
      Map.new(state.panels, fn {i, panel} -> {i, Panel.step(panel, config)} end)

    canvas =
      panels
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(&elem(&1, 1))
      |> Enum.map(&Panel.draw/1)
      |> Enum.reduce(&Canvas.join(&2, &1))

    update_display(canvas)

    {:noreply, %{state | panels: panels}}
  end

  def handle_event(%Input{type: :button, action: :press} = input, %State{} = state) do
    index = input.button - 1
    config = get_config(state)

    panels =
      Map.update(state.panels, index, nil, &Panel.handle_button_press(&1, config))

    {:noreply, %{state | panels: panels}}
  end

  def handle_event(_event, state) do
    {:noreply, state}
  end

  defp apply_config(%State{} = state, config) do
    config = coerce_config_atoms(config)
    defaults = legacy_mode_config("sand")

    %State{
      state
      | spawn_rate: Map.get(config, :spawn_rate, Map.get(state, :spawn_rate) || defaults.spawn_rate),
        button_force:
          Map.get(config, :button_force, Map.get(state, :button_force) || defaults.button_force),
        auto_drain: Map.get(config, :auto_drain, Map.get(state, :auto_drain) || defaults.auto_drain),
        color_mode: Map.get(config, :color_mode, Map.get(state, :color_mode) || defaults.color_mode)
    }
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
