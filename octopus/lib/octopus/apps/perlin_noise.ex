defmodule Octopus.Apps.PerlinNoise do
  use Octopus.App, category: :animation, output_type: :grayscale

  @mode_presets Module.concat(["Octopus", "AppModePresets"])

  alias Octopus.Canvas
  alias Octopus.Installation

  @fps 30
  @frame_time_ms trunc(1000 / @fps)
  @two_pi 2.0 * :math.pi()
  @default_contrast 3.0

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
      scale: default_scale(),
      octaves: 4,
      persistence: 0.5,
      speed: 1.0,
      seed: 42,
      contrast: @default_contrast
    }
  end

  def legacy_mode_config(_), do: %{}

  def mode_tweakables(mode_id) do
    mode_tweakables_for(apply(@mode_presets, :mode_slug, [mode_id]))
  end

  def mode_tweakables_for("perlin") do
    [
      %{
        key: :contrast,
        label: "Contrast",
        type: :slider,
        min: 0.5,
        max: 8.0,
        step: 0.5,
        default: @default_contrast
      },
      %{
        key: :scale,
        label: "Detail",
        type: :slider,
        min: 0.01,
        max: 0.5,
        step: 0.01,
        default: default_scale()
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
    scale = Map.get(config, :scale, default_scale())
    speed = Map.get(config, :speed, 1.0)
    contrast = Map.get(config, :contrast, @default_contrast)

    [
      "contrast #{format_num(contrast)}",
      "detail #{format_num(scale)}",
      "speed #{format_num(speed)}"
    ]
  end

  def compatible? do
    installation = Octopus.App.get_installation_info()

    installation.panel_count >= 1
  end

  def app_init(config) do
    # Instant panel updates — easing on the firmware side blurs full-frame noise.
    Octopus.App.configure_display(
      layout: :adjacent_panels,
      supports_rgb: false,
      supports_grayscale: true,
      easing_interval: 0
    )

    # Start animation timer
    :timer.send_after(@frame_time_ms, :tick)

    state = %{
      time: 0.0,
      scale: Map.get(config, :scale, default_scale()),
      octaves: Map.get(config, :octaves, 4),
      persistence: Map.get(config, :persistence, 0.5),
      speed: Map.get(config, :speed, 1.0),
      seed: Map.get(config, :seed, 42),
      contrast: Map.get(config, :contrast, @default_contrast)
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
      scale: {"Detail", :float, %{min: 0.01, max: 0.5, default: default_scale()}},
      octaves: {"Octaves", :int, %{min: 1, max: 8, default: 4}},
      persistence: {"Persistence", :float, %{min: 0.1, max: 1.0, default: 0.5}},
      speed: {"Speed", :float, %{min: 0.1, max: 3.0, default: 1.0}},
      seed: {"Seed", :int, %{min: 1, max: 9999, default: 42}},
      contrast: {"Contrast", :float, %{min: 0.5, max: 8.0, default: @default_contrast}}
    }
  end

  def get_config(state) do
    %{
      scale: state.scale,
      octaves: state.octaves,
      persistence: state.persistence,
      speed: state.speed,
      seed: state.seed,
      contrast: state.contrast
    }
  end

  def handle_config(config, state) do
    new_state = %{
      state
      | scale: Map.get(config, :scale, state.scale),
        octaves: Map.get(config, :octaves, state.octaves),
        persistence: Map.get(config, :persistence, state.persistence),
        speed: Map.get(config, :speed, state.speed),
        seed: Map.get(config, :seed, state.seed),
        contrast: Map.get(config, :contrast, state.contrast)
    }

    {:noreply, new_state}
  end

  @doc false
  def default_scale, do: 2.5 / Installation.panel_width()

  @doc false
  def render_canvas(width, height, state) do
    generate_perlin_canvas(width, height, state)
  end

  # Generate a canvas filled with Perlin noise
  defp generate_perlin_canvas(width, height, state) do
    canvas = Canvas.new(width, height, :grayscale)

    pixels =
      for x <- 0..(width - 1),
          y <- 0..(height - 1),
          into: %{} do
        {sample_x, sample_y, sample_z} = noise_sample_coords(x, y, width, state)

        noise_value =
          multi_octave_noise_3d(
            sample_x,
            sample_y,
            sample_z,
            state.octaves,
            state.persistence,
            state.seed
          )

        gray_value = trunc((noise_value + 1) * 127.5) |> max(0) |> min(255)
        normalized = gray_value / 255.0
        final_value = apply_contrast(normalized, state.contrast) |> trunc() |> max(0) |> min(255)

        {{x, y}, final_value}
      end

    %Canvas{canvas | pixels: pixels}
  end

  defp noise_sample_coords(x, y, width, state) do
    time_z = state.time * 0.25

    case Installation.arrangement() do
      :circular ->
        theta = x / max(width, 1) * @two_pi
        ring_radius = width / @two_pi * state.scale

        {
          :math.cos(theta) * ring_radius,
          y * state.scale,
          :math.sin(theta) * ring_radius + time_z
        }

      _ ->
        {x * state.scale, y * state.scale, time_z}
    end
  end

  defp apply_contrast(normalized, contrast) do
    s_curve = 1.0 / (1.0 + :math.exp(-contrast * (normalized - 0.5)))

    if contrast <= 1.0 do
      s_curve * 255.0
    else
      compressed =
        if s_curve < 0.5 do
          :math.pow(s_curve * 2.0, contrast) / 2.0
        else
          1.0 - :math.pow((1.0 - s_curve) * 2.0, contrast) / 2.0
        end

      compressed * 255.0
    end
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
