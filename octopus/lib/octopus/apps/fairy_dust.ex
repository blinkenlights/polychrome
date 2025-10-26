defmodule Octopus.Apps.FairyDust do
  use Octopus.App, category: :animation

  alias Octopus.{Canvas, Image, WebP}

  @fps 60

  defmodule State do
    defstruct [:fairy_dust, :time, :particles, :speed, :global_speed]
  end

  defmodule Particle do
    defstruct [:color, :x, :y, :vx, :vy, :ttl]
  end

  def name(), do: "Fairy Dust"

  def icon(), do: WebP.load("fairy-dust")

  def config_schema do
    %{
      speed: {"Speed", :float, %{default: 0.5, min: 0.1, max: 1}}
    }
  end

  def app_init(%{speed: speed}) do
    # Configure display using new unified API - gapped layout
    Octopus.App.configure_display(layout: :gapped_panels)

    # Subscribe to global parameter changes
    Octopus.Params.Global.subscribe()

    # Read initial global speed value
    global_speed = Octopus.Params.Global.speed()

    :timer.send_interval(trunc(1000 / @fps), :tick)

    fairy_dust = Image.load("fairy-dust")

    {:ok,
     %State{
       fairy_dust: fairy_dust,
       time: 0,
       particles: [],
       speed: speed,
       global_speed: global_speed
     }}
  end

  def handle_config(%{speed: speed}, %State{} = state) do
    {:noreply, %{state | speed: speed}}
  end

  def get_config(%State{speed: speed}) do
    %{speed: speed}
  end

  defp update_particles(particles, dt) do
    particles
    |> Enum.map(fn %Particle{} = particle ->
      %Particle{
        particle
        | x: particle.x + particle.vx * dt,
          y: particle.y + particle.vy * dt,
          ttl: particle.ttl - dt
      }
    end)
    |> Enum.filter(fn particle -> particle.ttl > 0 end)
  end

  defp draw_particles(particles, canvas_width) do
    particle_size = 1

    # find required maximal size, then draw according to colors
    max_x = Enum.reduce(particles, 0, fn particle, acc -> max(acc, particle.x) end)

    canvas = Canvas.new(trunc(max(max_x + 1, canvas_width)), 8)

    particles = particles |> Enum.filter(fn particle -> particle.x >= 0 and particle.y >= 0 end)

    Enum.reduce(particles, canvas, fn particle, canvas ->
      color =
        if particle.ttl < 1 do
          {r, g, b} = particle.color
          {trunc(r * particle.ttl), trunc(g * particle.ttl), trunc(b * particle.ttl)}
        else
          particle.color
        end

      Canvas.fill_rect(
        canvas,
        {trunc(particle.x - particle_size / 2), trunc(particle.y - particle_size / 2)},
        {trunc(particle.x + particle_size / 2 - 1), trunc(particle.y + particle_size / 2 - 1)},
        color
      )
    end)
  end

  def handle_info({:param_updated, :speed, new_value}, %State{} = state) do
    # Global speed parameter changed - update stored value
    {:noreply, %{state | global_speed: new_value}}
  end

  def handle_info({:param_updated, _key, _value}, %State{} = state) do
    # Other global parameters changed - ignore
    {:noreply, state}
  end

  def handle_info(:tick, %State{} = state) do
    dt = 1 / @fps * state.speed * state.global_speed

    # Get display info instead of virtual_matrix
    display_info = Octopus.App.get_display_info()
    canvas = Canvas.new(display_info.width, display_info.height)

    wrap_width = canvas.width + 100
    wrap_offset = -60
    rocket_speed = 100

    rocket_x =
      trunc(wrap_offset + abs(rem(trunc(state.time * rocket_speed), wrap_width * 2) - wrap_width))

    rocket_y = 4 + trunc(:math.sin(state.time * 4) * 4)
    rocket_dir = trunc(rem(trunc(state.time * rocket_speed), wrap_width * 2) / wrap_width) * 2 - 1

    # Rainbow flag
    particle_colors = [
      {228, 3, 3},
      {225, 140, 0},
      {255, 237, 0},
      {0, 128, 38},
      {0, 77, 255},
      {117, 7, 135}
    ]

    speed = 10
    particles = state.particles

    particles =
      Enum.reduce(0..(length(particle_colors) - 1), particles, fn i, acc ->
        [
          %Particle{
            color: Enum.at(particle_colors, i),
            x: rocket_x + :rand.uniform() * 2 - 1,
            y: rocket_y + (i - 2),
            vx: -(:rand.uniform() * 0.5 + 0.5) * speed * rocket_dir,
            vy: (:rand.uniform() - 0.5) * speed / 2,
            ttl: :rand.uniform() * 1 + 0.5
          }
          | acc
        ]
      end)

    particles = update_particles(particles, dt)

    particle_canvas = draw_particles(particles, canvas.width)

    fairy_dust =
      if rocket_dir == -1 do
        Canvas.flip(state.fairy_dust, :horizontal)
      else
        state.fairy_dust
      end

    canvas =
      canvas
      |> Canvas.overlay(particle_canvas)
      |> Canvas.overlay(fairy_dust,
        offset: {trunc(rocket_x - fairy_dust.width / 2), trunc(rocket_y - fairy_dust.height / 2)}
      )

    # Use new unified display API
    Octopus.App.update_display(canvas)

    {:noreply, %State{state | time: state.time + dt, particles: particles}}
  end
end
