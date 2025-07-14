defmodule Octopus.Particles do
  @moduledoc """
  A generic particle system.

  Example:

      system = Particles.new(16, 16, :math.pi() * 3.5, 0.05, {255, 0, 0})
      system = Particles.spawn(system, {7.5, 7.5}, 25)
      system = Particles.update(system, 0.1)
      canvas = Particles.draw(system, Canvas.new(16, 16))
  """

  alias Octopus.Canvas
  alias __MODULE__, as: Particles

  defmodule Particle do
    defstruct [:x, :y, :vx, :vy, :color, :ttl]

    @type t() :: %Particle{
            x: float(),
            y: float(),
            vx: float(),
            vy: float(),
            color: Canvas.color(),
            ttl: float()
          }
  end

  defstruct [
    :width,
    :height,
    :particles,
    :angle,
    :spread,
    :colors,
    :min_ttl,
    :max_ttl,
    :min_speed,
    :max_speed
  ]

  @type colors :: Canvas.color() | Enumerable.t()

  @type t() :: %Particles{
          width: integer(),
          height: integer(),
          particles: list(Particle.t()),
          angle: float(),
          spread: float(),
          colors: colors(),
          min_ttl: float(),
          max_ttl: float(),
          min_speed: float(),
          max_speed: float()
        }

  @doc """
  Creates a new particle system.

  ## Parameters
  - `width`: The width of the particle system
  - `height`: The height of the particle system
  - `angle`: The angle to spawn the particles at, in radians
  - `spread`: How much to spread the particles out, 0 is no spread, 1 is full spread (360 degrees)
  - `colors`: The colors to spawn the particles in, can be a single color or an enumerable of colors
  - `min_ttl`: The minimum time to live for the particles, in seconds
  - `max_ttl`: The maximum time to live for the particles, in seconds
  - `min_speed`: The minimum speed for the particles, in pixels per second
  - `max_speed`: The maximum speed for the particles, in pixels per second
  """

  @spec new(integer(), integer(), float(), float(), colors(), float(), float(), float(), float()) ::
          t()
  def new(
        width,
        height,
        angle,
        spread,
        colors,
        min_ttl \\ 0.5,
        max_ttl \\ 2.5,
        min_speed \\ 25,
        max_speed \\ 50
      ) do
    colors =
      case colors do
        {_, _, _} -> Stream.cycle([colors])
        colors -> Stream.cycle(colors)
      end

    %Particles{
      width: width,
      height: height,
      particles: [],
      angle: angle,
      spread: spread,
      colors: colors,
      min_ttl: min_ttl,
      max_ttl: max_ttl,
      min_speed: min_speed,
      max_speed: max_speed
    }
  end

  @doc """
  Spawns a number of particles at a given coordinate.

  ## Parameters
  - `particles`: The particles struct
  - `coord`: The coordinate to spawn the particles at
  - `amount`: The number of particles to spawn
  - `opts`: Additional options
    - `angle`: The angle to spawn the particles at, in radians
    - `spread`: How much to spread the particles out, 0 is no spread, 1 is full spread (360 degrees)
    - `colors`: The colors to spawn the particles in, can be a single color or an enumerable of colors
    - `min_ttl`: The minimum time to live for the particles, in seconds
    - `max_ttl`: The maximum time to live for the particles, in seconds
    - `min_speed`: The minimum speed for the particles, in pixels per second
    - `max_speed`: The maximum speed for the particles, in pixels per second
  """
  @spec spawn(t(), Canvas.coord(), non_neg_integer()) :: t()
  def spawn(%Particles{} = system, {x, y}, amount, opts \\ []) do
    angle = Keyword.get(opts, :angle, system.angle)
    spread = Keyword.get(opts, :spread, system.spread)
    min_ttl = Keyword.get(opts, :min_ttl, system.min_ttl)
    max_ttl = Keyword.get(opts, :max_ttl, system.max_ttl)
    min_speed = Keyword.get(opts, :min_speed, system.min_speed)
    max_speed = Keyword.get(opts, :max_speed, system.max_speed)

    colors =
      case Keyword.get(opts, :colors) do
        nil -> system.colors
        {_, _, _} = color -> Stream.cycle([color])
        colors -> Stream.cycle(colors)
      end

    new_particles =
      colors
      |> Enum.take(amount)
      |> Enum.map(fn color ->
        variance = (:rand.uniform() - 0.5) * 2 * spread * :math.pi() * 2
        angle_with_variance = angle + variance
        speed = :rand.uniform() * (max_speed - min_speed) + min_speed
        {vx, vy} = vector_from_angle(angle_with_variance)
        ttl = :rand.uniform() * (max_ttl - min_ttl) + min_ttl
        %Particle{x: x, y: y, vx: vx * speed, vy: vy * speed, color: color, ttl: ttl}
      end)

    %Particles{system | particles: system.particles ++ new_particles}
  end

  defp vector_from_angle(angle) do
    x = :math.cos(angle)
    y = :math.sin(angle)
    {x, y}
  end

  @spec update(t(), float()) :: t()
  def update(%Particles{} = system, dt) do
    particles =
      system.particles
      |> Enum.map(fn particle ->
        vx = particle.vx
        vy = particle.vy + 90.81 * dt

        %Particle{
          particle
          | vx: vx,
            vy: vy,
            x: particle.x + vx * dt,
            y: particle.y + vy * dt,
            ttl: particle.ttl - dt
        }
      end)
      |> Enum.filter(fn particle -> particle.ttl > 0 end)

    %Particles{system | particles: particles}
  end

  @doc """
  Draws all particles that are within the bounds of the particle system onto a canvas.

  ## Parameters
  - `system`: The particles struct
  - `canvas`: The canvas to draw the particles on
  - `offset`: The offset to draw the particles at, in pixels
  """
  @spec draw(t(), Canvas.t(), {integer(), integer()}) :: Canvas.t()
  def draw(%Particles{} = system, canvas, {dx, dy} \\ {0, 0}) do
    particles =
      system.particles
      |> Enum.filter(fn particle ->
        particle.x >= 0 and particle.y >= 0 and particle.x < system.width and
          particle.y < system.height
      end)

    Enum.reduce(particles, canvas, fn particle, canvas ->
      color =
        if particle.ttl < 1 do
          {r, g, b} = particle.color
          {trunc(r * particle.ttl), trunc(g * particle.ttl), trunc(b * particle.ttl)}
        else
          particle.color
        end

      Canvas.put_pixel(canvas, {round(particle.x + dx), round(particle.y + dy)}, color)
    end)
  end
end
