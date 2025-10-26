defmodule Octopus.PerlinNoise do
  @moduledoc """
  A Perlin noise generator that can be used to create animated noise patterns.

  Example:

      noise = PerlinNoise.new(scale: 0.1, octaves: 4, seed: 42)
      canvas = PerlinNoise.draw(noise, canvas, elapsed_time)
  """

  alias Octopus.Canvas
  alias __MODULE__, as: PerlinNoise

  defstruct [
    :scale,
    :octaves,
    :persistence,
    :speed,
    :seed
  ]

  @type t() :: %PerlinNoise{
          scale: float(),
          octaves: integer(),
          persistence: float(),
          speed: float(),
          seed: integer()
        }

  @doc """
  Creates a new Perlin noise generator.

  ## Parameters
  - `scale`: The scale of the noise pattern (default: 0.1)
  - `octaves`: Number of octaves for multi-octave noise (default: 4)
  - `persistence`: How much each octave contributes to the overall shape (default: 0.5)
  - `speed`: Animation speed multiplier (default: 1.0)
  - `seed`: Random seed for consistent patterns (default: random)
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %PerlinNoise{
      scale: Keyword.get(opts, :scale, 0.1),
      octaves: Keyword.get(opts, :octaves, 4),
      persistence: Keyword.get(opts, :persistence, 0.5),
      speed: Keyword.get(opts, :speed, 1.0),
      seed: Keyword.get(opts, :seed, :rand.uniform(1000))
    }
  end

  @doc """
  Draws Perlin noise onto a canvas.

  ## Parameters
  - `noise`: The PerlinNoise struct
  - `canvas`: The canvas to draw on
  - `elapsed_time`: Time elapsed in seconds
  """
  @spec draw(t(), Canvas.t(), float()) :: Canvas.t()
  def draw(%PerlinNoise{} = noise, %Canvas{} = canvas, elapsed_time) do
    # Calculate current time based on elapsed time and speed
    current_time = elapsed_time * noise.speed

    # Generate noise for each pixel
    pixels =
      for x <- 0..(canvas.width - 1),
          y <- 0..(canvas.height - 1),
          into: %{} do
        # Sample Perlin noise at this coordinate with time as Z dimension for stationary evolution
        sample_x = x * noise.scale
        sample_y = y * noise.scale
        # Use time as third dimension for evolution (25% faster)
        sample_z = current_time * 0.25

        noise_value =
          multi_octave_noise_3d(
            sample_x,
            sample_y,
            sample_z,
            noise.octaves,
            noise.persistence,
            noise.seed
          )

        # Normalize from [-1, 1] to [0, 255] with balanced high contrast
        gray_value = trunc((noise_value + 1) * 127.5) |> max(0) |> min(255)
        normalized = gray_value / 255.0

        # Use S-curve (sigmoid-like) for high contrast while preserving overall brightness balance
        # This pushes values toward 0 and 1 while keeping the average around 0.5
        contrast_factor = 3.0
        s_curve = 1.0 / (1.0 + :math.exp(-contrast_factor * (normalized - 0.5)))

        # Final compression filter: push values more aggressively toward extremes
        # Values below 0.5 get compressed toward 0, values above 0.5 get compressed toward 1
        # How aggressive the compression is
        compression_factor = 3.0

        compressed =
          if s_curve < 0.5 do
            # Compress dark values toward 0
            :math.pow(s_curve * 2.0, compression_factor) / 2.0
          else
            # Compress bright values toward 1
            1.0 - :math.pow((1.0 - s_curve) * 2.0, compression_factor) / 2.0
          end

        final_value = trunc(compressed * 255) |> max(0) |> min(255)

        {{x, y}, {final_value, final_value, final_value}}
      end

    %Canvas{canvas | pixels: pixels}
  end

  # Multi-octave 3D Perlin noise implementation for stationary evolution
  def multi_octave_noise_3d(x, y, z, octaves, persistence, seed) do
    total = 0.0
    frequency = 1.0
    amplitude = 1.0

    for octave <- 0..(octaves - 1), reduce: {total, frequency, amplitude} do
      {acc_total, freq, amp} ->
        sample_x = x * freq
        sample_y = y * freq
        sample_z = z * freq

        noise_val = noise_3d(sample_x, sample_y, sample_z, seed + octave)
        new_total = acc_total + noise_val * amp

        {new_total, freq * 2.0, amp * persistence}
    end
    |> elem(0)
    |> then(fn total -> total / (1 - :math.pow(persistence, octaves)) end)
    |> then(fn value -> value * 2 end)
  end

  # 3D Perlin noise function for stationary evolution
  defp noise_3d(x, y, z, seed) do
    # Get integer grid coordinates
    x0 = floor(x)
    x1 = x0 + 1
    y0 = floor(y)
    y1 = y0 + 1
    z0 = floor(z)
    z1 = z0 + 1

    # Get fractional parts for interpolation
    sx = x - x0
    sy = y - y0
    sz = z - z0

    # Generate gradients at eight corners and compute dot products
    n000 = dot_grid_gradient_3d(x0, y0, z0, x, y, z, seed)
    n100 = dot_grid_gradient_3d(x1, y0, z0, x, y, z, seed)
    n010 = dot_grid_gradient_3d(x0, y1, z0, x, y, z, seed)
    n110 = dot_grid_gradient_3d(x1, y1, z0, x, y, z, seed)
    n001 = dot_grid_gradient_3d(x0, y0, z1, x, y, z, seed)
    n101 = dot_grid_gradient_3d(x1, y0, z1, x, y, z, seed)
    n011 = dot_grid_gradient_3d(x0, y1, z1, x, y, z, seed)
    n111 = dot_grid_gradient_3d(x1, y1, z1, x, y, z, seed)

    # Smooth interpolation
    sx_smooth = smooth_step(sx)
    sy_smooth = smooth_step(sy)
    sz_smooth = smooth_step(sz)

    # Interpolate between the eight values
    lerp(
      lerp(
        lerp(n000, n100, sx_smooth),
        lerp(n010, n110, sx_smooth),
        sy_smooth
      ),
      lerp(
        lerp(n001, n101, sx_smooth),
        lerp(n011, n111, sx_smooth),
        sy_smooth
      ),
      sz_smooth
    )
  end

  # Compute dot product of 3D gradient and distance vectors
  defp dot_grid_gradient_3d(ix, iy, iz, x, y, z, seed) do
    # Get gradient vector
    {gx, gy, gz} = gradient_3d(ix, iy, iz, seed)

    # Distance vector
    dx = x - ix
    dy = y - iy
    dz = z - iz

    # Dot product
    gx * dx + gy * dy + gz * dz
  end

  # Generate consistent pseudo-random 3D gradient vector
  defp gradient_3d(x, y, z, seed) do
    # Hash the coordinates with seed
    hash = hash_coords_3d(x, y, z, seed)

    # Convert hash to spherical coordinates
    theta = hash * :math.pi() / 180.0
    phi = ((hash * 7) |> rem(360)) * :math.pi() / 180.0

    # Return unit vector in 3D
    {
      :math.sin(theta) * :math.cos(phi),
      :math.sin(theta) * :math.sin(phi),
      :math.cos(theta)
    }
  end

  # Simple hash function for 3D coordinates
  defp hash_coords_3d(x, y, z, seed) do
    # Simple hash combining x, y, z, and seed
    hash =
      (x * 374_761_393 + y * 668_265_263 + z * 1_597_334_677 + seed * 2_147_483_647)
      |> abs()
      |> rem(360)

    hash
  end

  # Smooth step function for interpolation
  defp smooth_step(t) do
    t * t * (3 - 2 * t)
  end

  # Linear interpolation
  defp lerp(a, b, t) do
    a + t * (b - a)
  end
end
