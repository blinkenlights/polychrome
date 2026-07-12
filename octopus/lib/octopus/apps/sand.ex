defmodule Octopus.Apps.Sand do
  use Octopus.App, category: :interactive

  @mode_presets Module.concat(["Octopus", "AppModePresets"])

  alias Octopus.Installation
  alias Octopus.Canvas
  alias Octopus.Apps.Sand.Sim
  alias Octopus.Events.Event.Input
  alias Octopus.Particles
  alias Octopus.Wander

  @fps 30
  @default_supersample 4
  @overflow_modes [:block, :waterfall, :abyss]

  defmodule State do
    defstruct [
      :sim,
      :particles,
      :panels,
      :display_info,
      :spawn_rate,
      :spawn_shape,
      :button_force,
      :auto_drain,
      :color_mode,
      :color_random_panels,
      :color_mix,
      :bleeding,
      :supersample,
      :gravity,
      :wind_strength,
      :wind_auto,
      :wind_auto_range,
      :wind_auto_interval,
      :overflow_mode,
      :overflow_auto,
      :overflow_auto_interval,
      :abyss_fate,
      :collapse_sensitivity,
      :collapse_cooldown,
      :plug_drain,
      :plug_drain_interval,
      :plug_drain_width,
      :plug_drain_duration,
      :show_advanced,
      :jet_from_panel,
      :jet_to_panel,
      :seconds,
      :wind_wanderer,
      :runtime_wind_strength,
      :runtime_overflow_mode,
      :overflow_last_mode,
      :overflow_next_at,
      :plug_x,
      :plug_open_until,
      :plug_next_at,
      :collapse_ready_at
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
      %{slug: "sand", name: "Sand", accent_color: "#E8A838", config: legacy_mode_config("sand")},
      %{slug: "dunes", name: "Dunes", accent_color: "#D4A574", config: legacy_mode_config("dunes")},
      %{
        slug: "hourglass",
        name: "Hourglass",
        accent_color: "#C9B896",
        config: legacy_mode_config("hourglass")
      },
      %{slug: "cascade", name: "Cascade", accent_color: "#6BB5C9", config: legacy_mode_config("cascade")},
      %{slug: "aurora", name: "Aurora", accent_color: "#9B6DFF", config: legacy_mode_config("aurora")},
      %{slug: "storm", name: "Storm", accent_color: "#5C7CFA", config: legacy_mode_config("storm")}
    ]
  end

  def legacy_mode_config("sand"), do: base_config()

  def legacy_mode_config("dunes") do
    base_config()
    |> Map.merge(%{
      spawn_rate: 0.2,
      wind_strength: 0.8,
      color_mix: 0.6,
      color_random_panels: 3
    })
  end

  def legacy_mode_config("hourglass") do
    base_config()
    |> Map.merge(%{
      spawn_rate: 0.08,
      spawn_shape: :fountain,
      collapse_sensitivity: 0.4,
      collapse_cooldown: 8.0,
      plug_drain: true,
      plug_drain_interval: 14.0,
      abyss_fate: :respawn
    })
  end

  def legacy_mode_config("cascade") do
    base_config()
    |> Map.merge(%{
      spawn_rate: 0.12,
      spawn_shape: :arc,
      overflow_mode: :waterfall,
      collapse_sensitivity: 0.25,
      collapse_cooldown: 4.0,
      plug_drain: true,
      plug_drain_interval: 10.0
    })
  end

  def legacy_mode_config("aurora") do
    num = max(Installation.num_panels(), 1)

    base_config()
    |> Map.merge(%{
      color_mode: :rainbow,
      color_mix: 0.8,
      color_random_panels: num,
      bleeding: 60.0
    })
  end

  def legacy_mode_config("storm") do
    base_config()
    |> Map.merge(%{
      spawn_shape: :arc,
      wind_auto: true,
      wind_auto_range: 2.0,
      wind_auto_interval: 25.0,
      overflow_auto: true,
      overflow_auto_interval: 20.0,
      plug_drain: true,
      plug_drain_interval: 8.0,
      auto_drain: false
    })
  end

  def legacy_mode_config(_), do: %{}

  defp base_config do
    s = @default_supersample
    num = max(Installation.num_panels(), 1)

    %{
      spawn_rate: 0.25,
      spawn_shape: :rain,
      button_force: 40,
      auto_drain: true,
      color_mode: :rainbow,
      color_random_panels: num,
      color_mix: 0.0,
      bleeding: 30.0,
      supersample: s,
      gravity: Sim.default_gravity(s),
      wind_strength: 0.0,
      wind_auto: false,
      wind_auto_range: 1.5,
      wind_auto_interval: 30.0,
      overflow_mode: :block,
      overflow_auto: false,
      overflow_auto_interval: 30.0,
      abyss_fate: :particles,
      collapse_sensitivity: 0.0,
      collapse_cooldown: 8.0,
      plug_drain: false,
      plug_drain_interval: 12.0,
      plug_drain_width: 2,
      plug_drain_duration: 1.5,
      show_advanced: false,
      jet_from_panel: 0,
      jet_to_panel: min(1, num - 1)
    }
  end

  def mode_tweakables(mode_id) do
    mode_tweakables_for(apply(@mode_presets, :mode_slug, [mode_id]))
  end

  def mode_tweakables_for(slug) when slug in ["sand", "dunes", "hourglass", "cascade", "aurora", "storm"] do
    s = @default_supersample
    g = Sim.default_gravity(s)
    num = max(Installation.num_panels(), 1)

    [
      %{key: :spawn_rate, label: "Spawn rate", type: :slider, min: 0.05, max: 0.8, step: 0.05, default: 0.25},
      %{
        key: :spawn_shape,
        label: "Spawn shape",
        type: :choice,
        default: :rain,
        options: [
          {:rain, "Rain"},
          {:fountain, "Fountain"},
          {:arc, "Arc"},
          {:jet, "Jet"}
        ]
      },
      %{key: :gravity, label: "Gravity", type: :slider, min: 0.0, max: 3.0, step: 0.05, default: g},
      %{
        key: :wind_strength,
        label: "Wind",
        type: :slider,
        min: -3.0,
        max: 3.0,
        step: 0.1,
        default: 0.0,
        auto_key: :wind_auto,
        disabled_when: {:wind_auto, [true]}
      },
      %{key: :wind_auto, label: "Auto", type: :toggle, default: false, companion_of: :wind_strength},
      %{
        key: :wind_auto_range,
        label: "Range",
        type: :slider,
        min: 0.0,
        max: 3.0,
        step: 0.1,
        default: 1.5,
        visible_when: {:wind_auto, [true]}
      },
      %{
        key: :wind_auto_interval,
        label: "Interval",
        type: :slider,
        min: 4.0,
        max: 120.0,
        step: 1.0,
        unit: "s",
        default: 30.0,
        visible_when: {:wind_auto, [true]}
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
        key: :color_random_panels,
        label: "Random panels",
        type: :slider,
        min: 1,
        max: num,
        step: 1,
        default: num,
        visible_when: {:color_mode, [:rainbow]}
      },
      %{
        key: :color_mix,
        label: "Color mix",
        type: :slider,
        min: 0.0,
        max: 100.0,
        step: 1.0,
        unit: "%",
        default: 0.0
      },
      %{
        key: :bleeding,
        label: "Bleeding",
        type: :slider,
        min: 0.0,
        max: 100.0,
        step: 1.0,
        unit: "%",
        default: 30.0,
        runtime: true
      },
      %{
        key: :overflow_mode,
        label: "Overflow",
        type: :choice,
        default: :block,
        options: [
          {:block, "Block"},
          {:waterfall, "Waterfall"},
          {:abyss, "Abyss"}
        ],
        disabled_when: {:overflow_auto, [true]}
      },
      %{key: :overflow_auto, label: "Overflow auto", type: :toggle, default: false},
      %{
        key: :overflow_auto_interval,
        label: "Interval",
        type: :slider,
        min: 4.0,
        max: 120.0,
        step: 1.0,
        unit: "s",
        default: 30.0,
        visible_when: {:overflow_auto, [true]}
      },
      %{
        key: :abyss_fate,
        label: "Abyss fate",
        type: :choice,
        default: :particles,
        options: [{:particles, "Particles"}, {:respawn, "Respawn"}],
        visible_when: {:overflow_mode, [:abyss]}
      },
      %{
        key: :collapse_sensitivity,
        label: "Collapse sense",
        type: :slider,
        min: 0.0,
        max: 100.0,
        step: 1.0,
        unit: "%",
        default: 0.0
      },
      %{
        key: :collapse_cooldown,
        label: "Collapse cooldown",
        type: :slider,
        min: 4.0,
        max: 60.0,
        step: 1.0,
        unit: "s",
        default: 8.0
      },
      %{key: :plug_drain, label: "Plug drain", type: :toggle, default: false},
      %{
        key: :plug_drain_interval,
        label: "Interval",
        type: :slider,
        min: 4.0,
        max: 60.0,
        step: 1.0,
        unit: "s",
        default: 12.0,
        visible_when: {:plug_drain, [true]}
      },
      %{
        key: :plug_drain_width,
        label: "Width",
        type: :slider,
        min: 1,
        max: 5,
        step: 1,
        default: 2,
        visible_when: {:plug_drain, [true]}
      },
      %{
        key: :plug_drain_duration,
        label: "Duration",
        type: :slider,
        min: 0.5,
        max: 3.0,
        step: 0.1,
        unit: "s",
        default: 1.5,
        visible_when: {:plug_drain, [true]}
      },
      %{key: :auto_drain, label: "Auto clear when full", type: :toggle, default: true},
      %{key: :show_advanced, label: "Advanced", type: :toggle, default: false, runtime: true},
      %{
        key: :jet_from_panel,
        label: "Jet from",
        type: :slider,
        min: 0,
        max: max(num - 1, 0),
        step: 1,
        default: 0,
        visible_when: {:show_advanced, [true]}
      },
      %{
        key: :jet_to_panel,
        label: "Jet to",
        type: :slider,
        min: 0,
        max: max(num - 1, 0),
        step: 1,
        default: min(1, max(num - 1, 0)),
        visible_when: {:show_advanced, [true]}
      },
      %{
        key: :supersample,
        label: "Supersample",
        type: :slider,
        min: 1,
        max: 6,
        step: 1,
        default: s,
        visible_when: {:show_advanced, [true]}
      }
    ]
  end

  def mode_tweakables_for(_), do: []

  def summary_for_preset(%{config: config}) do
    config = normalize_mode_config(config)

    wind =
      if Map.get(config, :wind_auto, false) do
        "wind auto"
      else
        "wind #{format_num(Map.get(config, :wind_strength, 0.0))}"
      end

    overflow =
      if Map.get(config, :overflow_auto, false) do
        "overflow auto"
      else
        "overflow #{Map.get(config, :overflow_mode, :block)}"
      end

    plug =
      if Map.get(config, :plug_drain, false) do
        "plug #{format_num(Map.get(config, :plug_drain_interval, 12.0))}s"
      else
        nil
      end

    [
      "spawn #{round(Map.get(config, :spawn_rate, 0.25) * 100)}%",
      wind,
      overflow,
      "mix #{round(Map.get(config, :color_mix, 0.0) * 100)}%",
      plug
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  def now_playing_meta(config) do
    config = normalize_mode_config(config)
    spawn_rate = Map.get(config, :spawn_rate, 0.25)
    shape = Map.get(config, :spawn_shape, :rain)
    gravity = Map.get(config, :gravity, Sim.default_gravity(@default_supersample))

    wind =
      if Map.get(config, :wind_auto, false),
        do: "wind auto",
        else: "wind #{format_num(Map.get(config, :wind_strength, 0.0))}"

    overflow =
      cond do
        Map.get(config, :overflow_auto, false) -> "overflow auto (#{Map.get(config, :overflow_mode, :block)})"
        true -> "overflow #{Map.get(config, :overflow_mode, :block)}"
      end

    lines = [
      "spawn #{round(spawn_rate * 100)}% · #{shape}",
      "#{wind} · grav #{format_num(gravity)}",
      overflow,
      "mix #{round(Map.get(config, :color_mix, 0.0) * 100)}%"
    ]

    lines =
      if Map.get(config, :plug_active, false) and config[:plug_x] != nil do
        lines ++ ["plug @ x=#{config.plug_x}"]
      else
        lines
      end

    lines
  end

  def config_schema do
    s = @default_supersample
    g = Sim.default_gravity(s)
    num = max(Installation.num_panels(), 1)

    %{
      spawn_rate: {"Spawn Rate", :float, %{default: 0.25, min: 0.05, max: 0.8, step: 0.05}},
      spawn_shape: {"Spawn Shape", :atom, %{default: :rain}},
      auto_drain: {"Auto Clear When Full", :boolean, %{default: true}},
      color_mode: {"Colors", :atom, %{default: :rainbow}},
      color_random_panels: {"Random Panels", :integer, %{default: num, min: 1, max: num}},
      color_mix: {"Color Mix", :float, %{default: 0.0, min: 0.0, max: 1.0, step: 0.01}},
      bleeding: {"Bleeding", :float, %{default: 30.0, min: 0.0, max: 100.0, step: 1.0}},
      supersample: {"Supersample", :integer, %{default: s, min: 1, max: 6}},
      gravity: {"Gravity", :float, %{default: g, min: 0.0, max: 3.0, step: 0.05}},
      wind_strength: {"Wind", :float, %{default: 0.0, min: -3.0, max: 3.0, step: 0.1}},
      wind_auto: {"Wind Auto", :boolean, %{default: false}},
      wind_auto_range: {"Wind Auto Range", :float, %{default: 1.5, min: 0.0, max: 3.0, step: 0.1}},
      wind_auto_interval: {"Wind Auto Interval", :float, %{default: 30.0, min: 4.0, max: 120.0, step: 1.0}},
      overflow_mode: {"Overflow", :atom, %{default: :block}},
      overflow_auto: {"Overflow Auto", :boolean, %{default: false}},
      overflow_auto_interval: {"Overflow Auto Interval", :float, %{default: 30.0, min: 4.0, max: 120.0, step: 1.0}},
      abyss_fate: {"Abyss Fate", :atom, %{default: :particles}},
      collapse_sensitivity: {"Collapse Sensitivity", :float, %{default: 0.0, min: 0.0, max: 1.0, step: 0.01}},
      collapse_cooldown: {"Collapse Cooldown", :float, %{default: 8.0, min: 4.0, max: 60.0, step: 1.0}},
      plug_drain: {"Plug Drain", :boolean, %{default: false}},
      plug_drain_interval: {"Plug Interval", :float, %{default: 12.0, min: 4.0, max: 60.0, step: 1.0}},
      plug_drain_width: {"Plug Width", :integer, %{default: 2, min: 1, max: 5}},
      plug_drain_duration: {"Plug Duration", :float, %{default: 1.5, min: 0.5, max: 3.0, step: 0.1}},
      show_advanced: {"Advanced", :boolean, %{default: false}},
      jet_from_panel: {"Jet From Panel", :integer, %{default: 0, min: 0, max: max(num - 1, 0)}},
      jet_to_panel: {"Jet To Panel", :integer, %{default: min(1, max(num - 1, 0)), min: 0, max: max(num - 1, 0)}},
      button_force: {"Button Blast", :integer, %{default: 40, min: 10, max: 80}}
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
          Particles.new(display_info.width, display_info.height, 0, 0, [{255, 255, 255}]),
        seconds: 0.0,
        overflow_last_mode: :block,
        overflow_next_at: 0.0,
        plug_next_at: 0.0,
        collapse_ready_at: 0.0
      }

    {:ok, apply_config(state, config)}
  end

  def handle_config(config, %State{} = state) do
    config =
      config
      |> Map.new()
      |> then(fn cfg ->
        if Map.has_key?(cfg, :overflow_mode) do
          Map.put(cfg, :overflow_auto, false)
        else
          cfg
        end
      end)

    {:noreply, apply_config(state, config)}
  end

  def get_config(%State{} = state) do
    overflow_mode =
      if state.overflow_auto,
        do: state.runtime_overflow_mode || state.overflow_mode,
        else: state.overflow_mode

    wind_strength =
      if state.wind_auto,
        do: state.runtime_wind_strength || state.wind_strength,
        else: state.wind_strength

    plug_active = state.plug_x != nil and state.seconds < (state.plug_open_until || 0.0)

    %{
      spawn_rate: state.spawn_rate,
      spawn_shape: state.spawn_shape,
      button_force: state.button_force,
      auto_drain: state.auto_drain,
      color_mode: state.color_mode,
      color_random_panels: state.color_random_panels,
      color_mix: (state.color_mix || 0.0) * 100,
      bleeding: state.bleeding,
      supersample: state.supersample,
      gravity: state.gravity,
      wind_strength: wind_strength,
      wind_auto: state.wind_auto,
      wind_auto_range: state.wind_auto_range,
      wind_auto_interval: state.wind_auto_interval,
      overflow_mode: overflow_mode,
      overflow_auto: state.overflow_auto,
      overflow_auto_interval: state.overflow_auto_interval,
      abyss_fate: state.abyss_fate,
      collapse_sensitivity: (state.collapse_sensitivity || 0.0) * 100,
      collapse_cooldown: state.collapse_cooldown,
      plug_drain: state.plug_drain,
      plug_drain_interval: state.plug_drain_interval,
      plug_drain_width: state.plug_drain_width,
      plug_drain_duration: state.plug_drain_duration,
      show_advanced: state.show_advanced,
      jet_from_panel: state.jet_from_panel,
      jet_to_panel: state.jet_to_panel,
      plug_x: state.plug_x,
      plug_active: plug_active
    }
  end

  def handle_info(:tick, %State{} = state) do
    dt = 1 / @fps

    state =
      state
      |> Map.update!(:seconds, &((&1 || 0.0) + dt))
      |> step_wind_auto()
      |> step_overflow_auto()
      |> step_plug_schedule()

    config = get_config(state)
    sim_ctx = sim_context(state, config)

    state = spawn_all_panels(state, config, sim_ctx)

    {sim, events} = Sim.step(state.sim, sim_ctx)
    {sim, particles} = handle_sim_events(sim, events, state.particles, state, config)

    state =
      %{state | sim: sim, particles: particles}
      |> maybe_collapse(config, sim_ctx)
      |> maybe_auto_drain(config)

    particles = Particles.update(state.particles, dt)

    canvas =
      state
      |> Map.put(:particles, particles)
      |> draw()

    update_display(canvas)

    {:noreply, %{state | particles: particles}}
  end

  def handle_event(%Input{type: :button, action: :press} = input, %State{} = state) do
    index = input.button - 1
    force = state.button_force || 40

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

  def handle_event(_event, state), do: {:noreply, state}

  defp step_wind_auto(%State{wind_auto: false} = state), do: state

  defp step_wind_auto(%State{} = state) do
    base = state.wind_strength || 0.0
    range = state.wind_auto_range || 1.5
    interval = state.wind_auto_interval || 30.0

    wanderer = state.wind_wanderer || Wander.new(base)

    {value, wanderer} =
      Wander.step(wanderer, state.seconds, %{
        min: max(base - range, -3.0),
        max: min(base + range, 3.0),
        interval: interval
      })

    %{state | wind_wanderer: wanderer, runtime_wind_strength: value}
  end

  defp step_overflow_auto(%State{overflow_auto: false} = state), do: state

  defp step_overflow_auto(%State{} = state) do
    if state.seconds >= (state.overflow_next_at || 0.0) do
      interval = state.overflow_auto_interval || 30.0
      last = state.overflow_last_mode || :block
      candidates = Enum.reject(@overflow_modes, &(&1 == last))
      mode = Enum.random(candidates)

      %{
        state
        | runtime_overflow_mode: mode,
          overflow_last_mode: mode,
          overflow_next_at: state.seconds + interval
      }
    else
      state
    end
  end

  defp step_plug_schedule(%State{plug_drain: false} = state), do: state

  defp step_plug_schedule(%State{} = state) do
    width = max(state.display_info.width - 1, 0)

    cond do
      state.plug_x != nil and state.seconds >= (state.plug_open_until || 0.0) ->
        %{state | plug_x: nil, plug_open_until: 0.0}

      state.plug_x == nil and state.seconds >= (state.plug_next_at || 0.0) ->
        %{
          state
          | plug_x: Enum.random(0..width),
            plug_open_until: state.seconds + (state.plug_drain_duration || 1.5),
            plug_next_at: state.seconds + (state.plug_drain_interval || 12.0)
        }

      true ->
        state
    end
  end

  defp sim_context(state, _config) do
    plug_active = state.plug_x != nil and state.seconds < (state.plug_open_until || 0.0)

    %{
      wind_strength: effective_wind(state),
      color_mix: state.color_mix || 0.0,
      overflow_mode: effective_overflow_mode(state),
      plug_x: state.plug_x,
      plug_width: state.plug_drain_width || 2,
      plug_active: plug_active
    }
  end

  defp effective_wind(%State{wind_auto: true} = state),
    do: state.runtime_wind_strength || state.wind_strength || 0.0

  defp effective_wind(%State{} = state), do: state.wind_strength || 0.0

  defp effective_overflow_mode(%State{overflow_auto: true} = state),
    do: state.runtime_overflow_mode || state.overflow_mode || :block

  defp effective_overflow_mode(%State{} = state), do: state.overflow_mode || :block

  defp spawn_all_panels(%State{} = state, config, sim_ctx) do
    sim =
      Enum.reduce(state.panels, state.sim, fn {_i, panel}, sim ->
        maybe_spawn_sand(sim, panel, state.display_info, config, sim_ctx)
      end)

    %{state | sim: sim}
  end

  defp maybe_spawn_sand(sim, _panel, _display_info, %{spawn_rate: rate}, _ctx) when rate <= 0, do: sim

  defp maybe_spawn_sand(sim, %Panel{} = panel, display_info, config, sim_ctx) do
    if :rand.uniform() > 1 - config.spawn_rate do
      {start_x, end_x} = display_info.panel_range.(panel.index, :x)
      color = random_color(panel, config)
      shape = Map.get(config, :spawn_shape, :rain)
      spawn_grains(sim, panel, start_x, end_x, color, shape, config, display_info, sim_ctx)
    else
      sim
    end
  end

  defp spawn_grains(sim, panel, panel_start_x, panel_end_x, color, :jet, config, display_info, _ctx) do
    from = config.jet_from_panel || 0
    to = config.jet_to_panel || 0
    num = display_info.num_panels

    if panel.index == rem(from, num) do
      {to_start, to_end} = display_info.panel_range.(rem(to, num), :x)
      target_x = div(to_start + to_end, 2)
      vx = (target_x - panel_start_x) * 0.25
      vy = -1.5

      sim_spawn_coords(sim, panel_start_x, panel_end_x, :jet)
      |> Enum.reduce(sim, fn {x, y, _vy0, _vx0}, sim ->
        Sim.put_cell(sim, {x, y}, Sim.sand(color, vy, vx), %{})
      end)
    else
      sim
    end
  end

  defp spawn_grains(sim, _panel, panel_start_x, panel_end_x, color, shape, _config, _display_info, _ctx) do
    drops = Enum.random(2..4)

    Enum.reduce(1..drops, sim, fn _, sim ->
      sim_spawn_coords(sim, panel_start_x, panel_end_x, shape)
      |> Enum.reduce(sim, fn {x, y, vy, vx}, sim ->
        Sim.put_cell(sim, {x, y}, Sim.sand(color, vy, vx), %{})
      end)
    end)
  end

  defp sim_spawn_coords(%Sim{supersample: s}, panel_start_x, panel_end_x, :fountain) do
    mid = div(panel_start_x + panel_end_x, 2)
    sim_x = mid * s + div(s, 2)
    spawn_y = Enum.random(0..(s - 1))

    for dy <- 0..1, do: {sim_x, spawn_y - dy, -1.5, 0.0}
  end

  defp sim_spawn_coords(%Sim{supersample: s}, panel_start_x, panel_end_x, :arc) do
    side = Enum.random([:left, :right])
    sim_start = panel_start_x * s
    sim_end = panel_end_x * s + (s - 1)

    sim_x =
      case side do
        :left -> sim_start
        :right -> sim_end
      end

    vx = if side == :left, do: 0.4, else: -0.4
    spawn_y = Enum.random(-s..-1)
    [{sim_x, spawn_y, 0.0, vx}]
  end

  defp sim_spawn_coords(%Sim{supersample: s}, panel_start_x, panel_end_x, :jet) do
    sim_start = panel_start_x * s
    sim_end = panel_end_x * s + (s - 1)
    sim_x = Enum.random(sim_start..sim_end)
    spawn_y = Enum.random(-s..-1)
    [{sim_x, spawn_y, -1.0, 0.0}]
  end

  defp sim_spawn_coords(%Sim{supersample: s}, panel_start_x, panel_end_x, _shape) do
    sim_start = panel_start_x * s
    sim_end = panel_end_x * s + (s - 1)
    sim_x = Enum.random(sim_start..sim_end)
    spawn_y = Enum.random(-s..-1)

    coords =
      if s >= 3 do
        cluster_x = min(sim_x, sim_end - 1)
        for dy <- 0..1, dx <- 0..1, do: {cluster_x + dx, spawn_y + dy}
      else
        [{sim_x, spawn_y}]
      end

    Enum.map(coords, fn {x, y} -> {x, y, 0.0, 0.0} end)
  end

  defp handle_sim_events(sim, events, particles, state, config) do
    Enum.reduce(events, {sim, particles}, fn
      {:plug_drain, coord, particle}, {sim, particles} ->
        {sim, spawn_particle_down(particles, particle, state.sim, coord)}

      {:abyss, coord, particle}, {sim, particles} ->
        case config.abyss_fate do
          :respawn ->
            {respawn_particle(sim, particle, state), particles}

          _ ->
            {sim, spawn_particle_down(particles, particle, state.sim, coord)}
        end
    end)
  end

  defp spawn_particle_down(particles, {:sand, color, _vy, _vx}, sim, {x, y}) do
    s = sim.supersample

    Particles.spawn(particles, {div(x, s), div(y, s)}, 1,
      angle: :math.pi() * 0.5,
      spread: 0.2,
      colors: color,
      min_speed: 8,
      max_speed: 20
    )
  end

  defp respawn_particle(sim, particle, state) do
    panel_index = Enum.random(Map.keys(state.panels))
    {start_x, end_x} = state.display_info.panel_range.(panel_index, :x)
    s = sim.supersample
    x = Enum.random(start_x..end_x) * s
    y = Enum.random(-s..-1)
    Sim.put_cell(sim, {x, y}, particle, %{})
  end

  defp maybe_collapse(%State{} = state, config, _sim_ctx) do
    sensitivity = (config.collapse_sensitivity || 0.0) / 100.0

    if sensitivity <= 0 or state.seconds < (state.collapse_ready_at || 0.0) do
      state
    else
      sim = state.sim
      s = sim.supersample
      panel_h = state.display_info.panel_height * s
      threshold = sensitivity * panel_h

      heights =
        sim
        |> Sim.column_heights()
        |> Enum.map(fn {x, y} -> {x, y} end)
        |> Map.new()

      unstable =
        heights
        |> Map.keys()
        |> Enum.filter(fn x ->
          h = Map.get(heights, x, panel_h)

          neighbors =
            [x - 1, x + 1]
            |> Enum.map(&Map.get(heights, &1, panel_h))

          Enum.any?(neighbors, fn nh -> h - nh > threshold end)
        end)

      if unstable == [] do
        state
      else
        %{
          state
          | sim: Sim.trigger_collapse(sim, unstable),
            collapse_ready_at: state.seconds + (config.collapse_cooldown || 8.0)
        }
      end
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
      _force = state.button_force || 40

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

    particle_canvas =
      Particles.draw(state.particles, Canvas.new(state.display_info.width, state.display_info.height))

    Enum.reduce(particle_canvas.pixels, canvas, fn {{x, y}, color}, canvas ->
      Canvas.put_pixel(canvas, {x, y}, color)
    end)
  end

  defp explode_panel(sim, particles, display_info, panel_index, min_force, max_force) do
    {start_x, end_x} = display_info.panel_range.(panel_index, :x)
    s = sim.supersample

    Enum.reduce(sim.particles, {sim, particles}, fn {{x, y}, particle}, {sim, particles} ->
      {:sand, color, _vy, _vx} = Sim.normalize_particle(particle)
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
  end

  defp random_color(%Panel{index: index}, config) do
    color_mode = Map.get(config, :color_mode, :rainbow)
    num_panels = max(Installation.num_panels(), 1)
    random_panels = max(Map.get(config, :color_random_panels, num_panels), 1)

    hue =
      case color_mode do
        :warm ->
          :rand.uniform() * 40 + 20

        :cool ->
          :rand.uniform() * 60 + 180

        :mono ->
          0

        _ ->
          palette_index = rem(index, random_panels)
          360 * palette_index / random_panels
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
    defaults = base_config()

    pick = fn key, default ->
      Map.get(config, key, Map.get(state, key) || default)
    end

    supersample = pick.(:supersample, defaults.supersample)
    gravity = pick.(:gravity, Sim.default_gravity(supersample))

    new_state = %State{
      state
      | spawn_rate: pick.(:spawn_rate, defaults.spawn_rate),
        spawn_shape: pick.(:spawn_shape, defaults.spawn_shape),
        button_force: pick.(:button_force, defaults.button_force),
        auto_drain: pick.(:auto_drain, defaults.auto_drain),
        color_mode: pick.(:color_mode, defaults.color_mode),
        color_random_panels: pick.(:color_random_panels, defaults.color_random_panels),
        color_mix: coerce_mix(pick.(:color_mix, defaults.color_mix)),
        bleeding: pick.(:bleeding, defaults.bleeding),
        supersample: supersample,
        gravity: gravity,
        wind_strength: pick.(:wind_strength, defaults.wind_strength),
        wind_auto: pick.(:wind_auto, defaults.wind_auto),
        wind_auto_range: pick.(:wind_auto_range, defaults.wind_auto_range),
        wind_auto_interval: pick.(:wind_auto_interval, defaults.wind_auto_interval),
        overflow_mode: pick.(:overflow_mode, defaults.overflow_mode),
        overflow_auto: pick.(:overflow_auto, defaults.overflow_auto),
        overflow_auto_interval: pick.(:overflow_auto_interval, defaults.overflow_auto_interval),
        abyss_fate: pick.(:abyss_fate, defaults.abyss_fate),
        collapse_sensitivity: coerce_mix(pick.(:collapse_sensitivity, defaults.collapse_sensitivity)),
        collapse_cooldown: pick.(:collapse_cooldown, defaults.collapse_cooldown),
        plug_drain: pick.(:plug_drain, defaults.plug_drain),
        plug_drain_interval: pick.(:plug_drain_interval, defaults.plug_drain_interval),
        plug_drain_width: pick.(:plug_drain_width, defaults.plug_drain_width),
        plug_drain_duration: pick.(:plug_drain_duration, defaults.plug_drain_duration),
        show_advanced: pick.(:show_advanced, defaults.show_advanced),
        jet_from_panel: pick.(:jet_from_panel, defaults.jet_from_panel),
        jet_to_panel: pick.(:jet_to_panel, defaults.jet_to_panel),
        runtime_overflow_mode:
          if(pick.(:overflow_auto, defaults.overflow_auto),
            do: state.runtime_overflow_mode || pick.(:overflow_mode, defaults.overflow_mode),
            else: nil
          ),
        overflow_last_mode:
          state.overflow_last_mode || pick.(:overflow_mode, defaults.overflow_mode),
        wind_wanderer: if(pick.(:wind_auto, defaults.wind_auto), do: state.wind_wanderer, else: nil)
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
      {:spawn_shape, value} -> {:spawn_shape, coerce_spawn_shape(value)}
      {:overflow_mode, value} -> {:overflow_mode, coerce_overflow_mode(value)}
      {:abyss_fate, value} -> {:abyss_fate, coerce_abyss_fate(value)}
      {:color_mix, value} -> {:color_mix, coerce_mix(value)}
      {:collapse_sensitivity, value} -> {:collapse_sensitivity, coerce_mix(value)}
      {key, value} when key in [:wind_auto, :overflow_auto, :plug_drain, :auto_drain, :show_advanced] ->
        {key, coerce_boolean(value)}

      {key, value} ->
        {key, value}
    end)
  end

  defp coerce_color_mode(value) when is_atom(value), do: value

  defp coerce_color_mode("warm"), do: :warm
  defp coerce_color_mode("cool"), do: :cool
  defp coerce_color_mode("mono"), do: :mono
  defp coerce_color_mode(_), do: :rainbow

  defp coerce_spawn_shape(value) when is_atom(value), do: value
  defp coerce_spawn_shape("fountain"), do: :fountain
  defp coerce_spawn_shape("arc"), do: :arc
  defp coerce_spawn_shape("jet"), do: :jet
  defp coerce_spawn_shape(_), do: :rain

  defp coerce_overflow_mode(value) when is_atom(value), do: value
  defp coerce_overflow_mode("waterfall"), do: :waterfall
  defp coerce_overflow_mode("abyss"), do: :abyss
  defp coerce_overflow_mode(_), do: :block

  defp coerce_abyss_fate(value) when is_atom(value), do: value
  defp coerce_abyss_fate("respawn"), do: :respawn
  defp coerce_abyss_fate(_), do: :particles

  defp coerce_mix(value) when is_number(value) and value > 1, do: value / 100.0
  defp coerce_mix(value) when is_number(value), do: value * 1.0
  defp coerce_mix(_), do: 0.0

  defp coerce_boolean(true), do: true
  defp coerce_boolean(false), do: false
  defp coerce_boolean("true"), do: true
  defp coerce_boolean("false"), do: false
  defp coerce_boolean(value) when value in [1, "1", "on"], do: true
  defp coerce_boolean(_), do: false

  defp format_num(n) when is_float(n), do: :erlang.float_to_binary(n, decimals: 1)
  defp format_num(n) when is_integer(n), do: Integer.to_string(n)
  defp format_num(n), do: to_string(n)
end
