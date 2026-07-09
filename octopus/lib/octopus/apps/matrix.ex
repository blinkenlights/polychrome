defmodule Octopus.Apps.Matrix do
  use Octopus.App, category: :animation

  @mode_presets Module.concat(["Octopus", "AppModePresets"])

  defmodule Particle do
    defstruct [:x, :y, :z, :speed, :color, :age, :max_age, :tail]
  end

  defmodule State do
    @greens [{164, 223, 179}, {86, 115, 70}, {44, 64, 11}, {22, 40, 0}]
    @pinks [{251, 72, 196}, {165, 52, 167}, {77, 40, 92}]

    alias Octopus.Canvas

    defstruct [
      :canvas,
      :particles,
      :width,
      :height,
      :global_speed,
      :speed,
      :density,
      :max_particles
    ]

    def spawn_particles(
          %State{particles: particles, width: width, height: height} = state,
          amount
        ) do
      new_particles =
        Enum.map(1..amount, fn _ ->
          speed =
            if :rand.uniform() > 0.9 do
              18.0
            else
              3.0 + :rand.uniform() * 12.0
            end

          %Particle{
            x: :rand.uniform(width) - 1,
            y: :rand.uniform(height) - 12,
            z: :rand.uniform() * 0.5 + 0.5,
            speed: speed,
            age: 0.0,
            max_age: 5 + :rand.uniform() * 6,
            tail: Enum.map(1..(4 + :rand.uniform(3)), fn _ -> Enum.random(@greens) end),
            color: {:rand.uniform(40), 200 + :rand.uniform(55), :rand.uniform(40)}
          }
        end)

      %State{state | particles: particles ++ new_particles}
    end

    def update(%State{} = state, dt) do
      particles =
        state.particles
        |> Enum.map(fn %Particle{x: x, y: y, speed: speed, age: age} = particle ->
          %Particle{
            particle
            | x: x,
              y: y + speed * dt,
              speed: speed,
              age: age + dt
          }
        end)
        |> Enum.filter(fn %Particle{y: y, age: age, max_age: max_age} ->
          y < state.height * 2 and age < max_age
        end)

      %State{state | particles: particles}
    end

    def render(%State{particles: particles, width: width, height: height} = state) do
      canvas = Canvas.new(width, height)

      canvas =
        particles
        |> Enum.sort_by(fn %Particle{z: z} -> z end)
        |> Enum.reduce(canvas, fn %Particle{x: x, y: y, age: _age} = particle, canvas ->
          canvas =
            particle.tail
            |> Enum.with_index()
            |> Enum.reduce(canvas, fn {color, i}, c ->
              Canvas.put_pixel(c, {trunc(x), trunc(y - i - 1)}, color)
            end)

          Canvas.put_pixel(canvas, {trunc(x), trunc(y)}, {150, 255, 150})
        end)

      %State{state | canvas: canvas}
    end

    def change_colors(%State{particles: particles} = state) do
      particles =
        particles
        |> Enum.map(fn %Particle{tail: tail} = particle ->
          tail =
            Enum.map(tail, fn color ->
              rand = :rand.uniform()

              cond do
                rand > 0.99 and color not in @pinks ->
                  if :rand.uniform() > 0.4, do: List.first(@greens), else: {0, 0, 0}

                rand > 0.9 and color not in @pinks ->
                  @greens |> Enum.drop(1) |> Enum.random()

                true ->
                  color
              end
            end)

          %Particle{particle | tail: tail}
        end)

      %State{state | particles: particles}
    end
  end

  alias Octopus.Canvas

  def name(), do: "Matrix"

  def list_modes do
    apply(@mode_presets, :list_modes, [__MODULE__])
  end

  def mode_config(mode_id) do
    (apply(@mode_presets, :config_for, [__MODULE__, mode_id]) ||
       legacy_mode_config(apply(@mode_presets, :mode_slug, [mode_id])))
  end

  def builtin_presets do
    [
      %{
        slug: "matrix",
        name: "matrix",
        accent_color: "#2ECC71",
        config: legacy_mode_config("matrix")
      }
    ]
  end

  def legacy_mode_config("matrix"), do: %{speed: 1.0, density: 3, max_particles: 200}
  def legacy_mode_config(_), do: %{}

  def mode_tweakables(mode_id) do
    mode_tweakables_for(apply(@mode_presets, :mode_slug, [mode_id]))
  end

  def mode_tweakables_for("matrix") do
    [
      %{
        key: :speed,
        label: "Speed",
        type: :slider,
        min: 0.1,
        max: 3.0,
        step: 0.1,
        default: 1.0
      },
      %{
        key: :density,
        label: "Density",
        type: :slider,
        min: 1,
        max: 10,
        step: 1,
        default: 3
      },
      %{
        key: :max_particles,
        label: "Max particles",
        type: :slider,
        min: 50,
        max: 400,
        step: 10,
        default: 200
      }
    ]
  end

  def mode_tweakables_for(_), do: []

  def compatible?() do
    installation = Octopus.App.get_installation_info()

    installation.panel_count >= 8 and installation.panel_width == 8 and
      installation.panel_height == 8
  end

  def get_config(%State{} = state) do
    %{
      speed: state.speed,
      density: state.density,
      max_particles: state.max_particles
    }
  end

  def handle_config(config, %State{} = state) do
    {:noreply, apply_config(state, config)}
  end

  def now_playing_meta(config) do
    max = Map.get(config, :max_particles, 200)
    density = Map.get(config, :density, 3)
    ["#{max} particles max", "density #{density}"]
  end

  def app_init(config) do
    Octopus.App.configure_display(layout: :adjacent_panels)
    Octopus.Params.Global.subscribe()

    global_speed = Octopus.Params.Global.speed()

    display_info = Octopus.App.get_display_info()
    width = display_info.width
    height = display_info.height

    canvas = Canvas.new(width, height)
    :timer.send_interval(trunc(1000 / 60), :tick)
    :timer.send_interval(50, :spawn_particles)
    :timer.send_interval(50, :change_colors)

    state =
      %State{
        canvas: canvas,
        particles: [],
        width: width,
        height: height,
        global_speed: global_speed,
        speed: 1.0,
        density: 3,
        max_particles: 200
      }
      |> apply_config(config)

    {:ok, state}
  end

  def handle_info({:param_updated, :speed, new_value}, %State{} = state) do
    {:noreply, %{state | global_speed: new_value}}
  end

  def handle_info({:param_updated, _key, _value}, %State{} = state) do
    {:noreply, state}
  end

  def handle_info(:change_colors, %State{} = state) do
    {:noreply, State.change_colors(state)}
  end

  def handle_info(:spawn_particles, %State{} = state) do
    state =
      if Enum.count(state.particles) < state.max_particles do
        State.spawn_particles(state, max(1, trunc(state.density)))
      else
        state
      end

    {:noreply, state}
  end

  def handle_info(:tick, %State{} = state) do
    dt = 1 / 60 * state.speed * state.global_speed
    state = state |> State.update(dt) |> State.render()
    Octopus.App.update_display(state.canvas)
    {:noreply, state}
  end

  defp apply_config(%State{} = state, config) do
    state
    |> maybe_put(:speed, config, 1.0)
    |> maybe_put(:density, config, 3)
    |> maybe_put(:max_particles, config, 200)
  end

  defp maybe_put(state, key, config, default) do
    Map.put(state, key, Map.get(config, key, Map.get(state, key) || default))
  end
end
