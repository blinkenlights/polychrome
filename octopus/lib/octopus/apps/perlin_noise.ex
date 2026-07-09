defmodule Octopus.Apps.PerlinNoise do
  use Octopus.App, category: :animation, output_type: :grayscale

  @mode_presets Module.concat(["Octopus", "AppModePresets"])

  alias Octopus.Canvas

  @fps 30
  @frame_time_ms trunc(1000 / @fps)

  def name, do: "Perlin Noise"

  def list_modes do
    apply(@mode_presets, :list_modes, [__MODULE__])
  end

  def mode_config(mode_id) do
    apply(@mode_presets, :config_for, [__MODULE__, mode_id]) ||
      legacy_mode_config(apply(@mode_presets, :mode_slug, [mode_id]))
  end

  def builtin_presets do
    [
      %{
        slug: "perlin",
        name: "Perlin noise",
        accent_color: "#95A5A6",
        config: legacy_mode_config("perlin")
      }
    ]
  end

  def legacy_mode_config("perlin") do
    %{
      scale: 0.1,
      octaves: 4,
      persistence: 0.5,
      speed: 1.0,
      seed: 42
    }
  end

  def legacy_mode_config(_), do: %{}

  def mode_tweakables(mode_id) do
    mode_tweakables_for(apply(@mode_presets, :mode_slug, [mode_id]))
  end

  def mode_tweakables_for("perlin") do
    [
      %{
        key: :scale,
        label: "Scale",
        type: :slider,
        min: 0.01,
        max: 0.5,
        step: 0.01,
        default: 0.1
      },
      %{
        key: :octaves,
        label: "Octaves",
        type: :slider,
        min: 1,
        max: 8,
        step: 1,
        default: 4
      },
      %{
        key: :persistence,
        label: "Persistence",
        type: :slider,
        min: 0.1,
        max: 1.0,
        step: 0.05,
        default: 0.5
      },
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
        key: :seed,
        label: "Seed",
        type: :slider,
        min: 1,
        max: 9999,
        step: 1,
        default: 42
      }
    ]
  end

  def mode_tweakables_for(_), do: []

  def now_playing_meta(config) do
    scale = Map.get(config, :scale, 0.1)
    octaves = Map.get(config, :octaves, 4)
    speed = Map.get(config, :speed, 1.0)

    ["scale #{format_num(scale)}", "#{octaves} octaves", "speed #{format_num(speed)}"]
  end

  def compatible? do
    installation = Octopus.App.get_installation_info()

    installation.panel_count >= 1
  end

  def app_init(config) do
    # Configure display for grayscale output using the new API
    Octopus.App.configure_display(
      layout: :adjacent_panels,
      supports_rgb: false,
      supports_grayscale: true,
      easing_interval: 50
    )

    # Start animation timer
    :timer.send_after(@frame_time_ms, :tick)

    state = %{
      time: 0.0,
      scale: Map.get(config, :scale, 0.1),
      octaves: Map.get(config, :octaves, 4),
      persistence: Map.get(config, :persistence, 0.5),
      speed: Map.get(config, :speed, 1.0),
      seed: Map.get(config, :seed, 42)
    }

    {:ok, state}
  end

  def handle_info(:tick, state) do
    # Schedule next frame
    :timer.send_after(@frame_time_ms, :tick)

    # Get display dimensions
    display_info = Octopus.App.get_display_info()

    # Generate Perlin noise canvas
    canvas = generate_perlin_canvas(display_info.width, display_info.height, state)

    # Send grayscale canvas to mixer
    Octopus.App.update_display(canvas, :grayscale)

    # Update time for animation
    new_time = state.time + state.speed / @fps
    {:noreply, %{state | time: new_time}}
  end

  def config_schema() do
    %{
      scale: {"Scale", :float, %{min: 0.01, max: 0.5, default: 0.1}},
      octaves: {"Octaves", :int, %{min: 1, max: 8, default: 4}},
      persistence: {"Persistence", :float, %{min: 0.1, max: 1.0, default: 0.5}},
      speed: {"Speed", :float, %{min: 0.1, max: 3.0, default: 1.0}},
      seed: {"Seed", :int, %{min: 1, max: 9999, default: 42}}
    }
  end

  def get_config(state) do
    %{
      scale: state.scale,
      octaves: state.octaves,
      persistence: state.persistence,
      speed: state.speed,
      seed: state.seed
    }
  end

  def handle_config(config, state) do
    new_state = %{
      state
      | scale: Map.get(config, :scale, state.scale),
        octaves: Map.get(config, :octaves, state.octaves),
        persistence: Map.get(config, :persistence, state.persistence),
        speed: Map.get(config, :speed, state.speed),
        seed: Map.get(config, :seed, state.seed)
    }

    {:noreply, new_state}
  end

  # Generate a canvas filled with Perlin noise
  defp generate_perlin_canvas(width, height, state) do
    canvas = Canvas.new(width, height, :grayscale)

    pixels =
      for x <- 0..(width - 1),
          y <- 0..(height - 1),
          into: %{} do
        # Sample Perlin noise at this coordinate with time as Z dimension for stationary evolution
        sample_x = x * state.scale
        sample_y = y * state.scale
        # Use time as third dimension for evolution (25% faster)
        sample_z = state.time * 0.25

        noise_value =
          multi_octave_noise_3d(
            sample_x,
            sample_y,
            sample_z,
            state.octaves,
            state.persistence,
            state.seed
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

        {{x, y}, final_value}
      end

    %Canvas{canvas | pixels: pixels}
  end

  # Multi-octave 3D Perlin noise implementation for stationary evolution
  defp multi_octave_noise_3d(x, y, z, octaves, persistence, seed) do
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

  defp format_num(n) when is_float(n), do: :erlang.float_to_binary(n, decimals: 2)
  defp format_num(n) when is_integer(n), do: Integer.to_string(n)
end
