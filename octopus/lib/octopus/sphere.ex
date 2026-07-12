defmodule Octopus.Sphere do
  @moduledoc """
  Unit-sphere projection for circular LED rings.

  Visible pixels sample a narrow equatorial band of a unit sphere. Pattern
  motion is SO(3) rotations (always seamless) plus an optional conformal
  Möbius dilation for zoom. Chart coordinates `(x_s, y_s)` stay in pixel
  units so classic formulas keep their familiar scale; `nx, ny, nz` expose
  the final direction for seam-free expressions.

  Large elevation offsets push the band toward the poles where azimuthal
  patterns compress — `|theta'|` is clamped below `pi/2 - epsilon`.
  """

  @type vec3 :: {float(), float(), float()}
  @type mat3 ::
          {float(), float(), float(), float(), float(), float(), float(), float(), float()}
  @type mobius_basis :: {vec3(), vec3(), vec3()}

  @epsilon 1.0e-9
  @theta_max :math.pi() / 2 - 1.0e-6

  @doc "Angular pitch in radians per virtual pixel (ring closes exactly)."
  @spec alpha(number()) :: float()
  def alpha(w) when w > 0, do: 2 * :math.pi() / w

  @doc """
  Pixel → unit direction. `z` is up; canvas `y` grows downward so elevation
  negates `(y - cy)`.
  """
  @spec direction(number(), number(), number(), number()) :: vec3()
  def direction(x, y, w, h) when w > 0 and h > 0 do
    a = alpha(w)
    cx = w / 2 - 0.5
    cy = h / 2 - 0.5
    phi = (x - cx) * a
    theta = -(y - cy) * a
    cos_t = :math.cos(theta)
    {cos_t * :math.cos(phi), cos_t * :math.sin(phi), :math.sin(theta)}
  end

  @doc "Yaw rotation about {0,0,1}."
  @spec rot_z(number()) :: mat3()
  def rot_z(a) do
    c = :math.cos(a)
    s = :math.sin(a)
    {c, -s, 0.0, s, c, 0.0, 0.0, 0.0, 1.0}
  end

  @doc "Rodrigues rotation about unit axis `u` by angle `a`."
  @spec rot_axis(vec3(), number()) :: mat3()
  def rot_axis({ux, uy, uz}, a) do
    c = :math.cos(a)
    s = :math.sin(a)
    one_c = 1.0 - c

    {
      c + ux * ux * one_c,
      ux * uy * one_c - uz * s,
      ux * uz * one_c + uy * s,
      uy * ux * one_c + uz * s,
      c + uy * uy * one_c,
      uy * uz * one_c - ux * s,
      uz * ux * one_c - uy * s,
      uz * uy * one_c + ux * s,
      c + uz * uz * one_c
    }
  end

  @doc "Matrix product `m1 · m2` (apply m2 first)."
  @spec mul(mat3(), mat3()) :: mat3()
  def mul(
        {a00, a01, a02, a10, a11, a12, a20, a21, a22},
        {b00, b01, b02, b10, b11, b12, b20, b21, b22}
      ) do
    {
      a00 * b00 + a01 * b10 + a02 * b20,
      a00 * b01 + a01 * b11 + a02 * b21,
      a00 * b02 + a01 * b12 + a02 * b22,
      a10 * b00 + a11 * b10 + a12 * b20,
      a10 * b01 + a11 * b11 + a12 * b21,
      a10 * b02 + a11 * b12 + a12 * b22,
      a20 * b00 + a21 * b10 + a22 * b20,
      a20 * b01 + a21 * b11 + a22 * b21,
      a20 * b02 + a21 * b12 + a22 * b22
    }
  end

  @doc "Apply rotation matrix to a vector (`M · v`)."
  @spec transform(mat3(), vec3()) :: vec3()
  def transform({m00, m01, m02, m10, m11, m12, m20, m21, m22}, {x, y, z}) do
    {
      m00 * x + m01 * y + m02 * z,
      m10 * x + m11 * y + m12 * z,
      m20 * x + m21 * y + m22 * z
    }
  end

  @doc """
  Orientation `M(t) = Rz(yaw) · Rtilt · Rroll` (outermost first).

  Options:
  - `:yaw` — rad
  - `:roll_angle` / `:roll_pivot_phi` — roll about horizontal pivot
  - `:tilt_amplitude` / `:tilt_speed` / `:tilt_mode` / `:t` — wobble or pendulum
  """
  @spec orientation(keyword()) :: mat3()
  def orientation(opts) do
    t = Keyword.get(opts, :t, 0.0)
    yaw = Keyword.get(opts, :yaw, 0.0)
    roll_angle = Keyword.get(opts, :roll_angle, 0.0)
    roll_pivot_phi = Keyword.get(opts, :roll_pivot_phi, 0.0)
    tilt_amplitude = Keyword.get(opts, :tilt_amplitude, 0.0)
    tilt_speed = Keyword.get(opts, :tilt_speed, 0.0)
    tilt_mode = Keyword.get(opts, :tilt_mode, :wobble)

    r_roll =
      if roll_angle == 0 do
        identity()
      else
        p = {:math.cos(roll_pivot_phi), :math.sin(roll_pivot_phi), 0.0}
        rot_axis(p, roll_angle)
      end

    r_tilt = tilt_matrix(tilt_mode, tilt_amplitude, tilt_speed, t)
    r_yaw = if yaw == 0, do: identity(), else: rot_z(yaw)

    mul(r_yaw, mul(r_tilt, r_roll))
  end

  defp tilt_matrix(_mode, amp, _speed, _t) when amp == 0, do: identity()

  defp tilt_matrix(:pendulum, amp, speed, t) do
    rot_axis({1.0, 0.0, 0.0}, amp * :math.sin(speed * t))
  end

  defp tilt_matrix(_wobble, amp, speed, t) do
    a = {:math.cos(speed * t), :math.sin(speed * t), 0.0}
    rot_axis(a, amp)
  end

  @doc "Orthonormal Möbius basis `{u, v, a}` with attractor `a` on the equator."
  @spec mobius_basis(number()) :: mobius_basis()
  def mobius_basis(phi_a) do
    a = {:math.cos(phi_a), :math.sin(phi_a), 0.0}
    z = {0.0, 0.0, 1.0}
    u = normalize(cross(a, z))
    u = if near_zero?(u), do: {1.0, 0.0, 0.0}, else: u
    v = cross(a, u)
    {u, v, a}
  end

  @doc """
  Conformal Möbius dilation toward attractor `a`. `sigma == 0` is identity.
  `zoom_rate` flow is endless; pattern appearance is periodic only if the
  formula cooperates — the flow itself never seams.
  """
  @spec dilate(vec3(), number(), mobius_basis()) :: vec3()
  def dilate(d, sigma, _basis) when sigma == 0, do: d

  def dilate({dx, dy, dz}, sigma, {{ux, uy, uz}, {vx, vy, vz}, {ax, ay, az}}) do
    den = 1.0 + dx * ax + dy * ay + dz * az

    if den < @epsilon do
      {-ax, -ay, -az}
    else
      zx = (dx * ux + dy * uy + dz * uz) / den
      zy = (dx * vx + dy * vy + dz * vz) / den
      k = :math.exp(sigma)
      zx = k * zx
      zy = k * zy
      s = zx * zx + zy * zy
      inv = 1.0 / (1.0 + s)
      # (1-s)/(1+s): s=0 → attractor a; s→∞ → repeller -a
      az_comp = (1.0 - s) * inv

      {
        2.0 * zx * inv * ux + 2.0 * zy * inv * vx + az_comp * ax,
        2.0 * zx * inv * uy + 2.0 * zy * inv * vy + az_comp * ay,
        2.0 * zx * inv * uz + 2.0 * zy * inv * vz + az_comp * az
      }
    end
  end

  @doc "Elevation offset in radians (pixel sliders × alpha)."
  @spec elev_offset(number(), number(), number(), number(), number()) :: float()
  def elev_offset(elev_base, elev_amp, elev_speed, t, alpha) do
    (elev_base + elev_amp * :math.sin(elev_speed * t)) * alpha
  end

  @doc """
  Direction → pixel-unit chart coords. At neutral orientation this matches
  centered canvas coords up to trig round-trip error. Azimuth remains
  periodic — classic formulas in `x` still need ring periodicity.
  """
  @spec to_chart(vec3(), number()) :: {float(), float()}
  def to_chart({dx, dy, dz}, alpha) when alpha > 0 do
    phi = :math.atan2(dy, dx)
    theta = :math.asin(clamp(dz, -1.0, 1.0))
    {phi / alpha, -theta / alpha}
  end

  @doc "Apply elevation in chart space, then rebuild a unit direction."
  @spec apply_elevation(vec3(), number(), number()) :: vec3()
  def apply_elevation(d, elev_rad, _alpha) when elev_rad == 0, do: d

  def apply_elevation({dx, dy, dz}, elev_rad, alpha) when alpha > 0 do
    phi = :math.atan2(dy, dx)
    theta = clamp(:math.asin(clamp(dz, -1.0, 1.0)) + elev_rad, -@theta_max, @theta_max)
    cos_t = :math.cos(theta)
    {cos_t * :math.cos(phi), cos_t * :math.sin(phi), :math.sin(theta)}
  end

  @doc """
  Full per-pixel sample: rotate → Möbius → elevation → chart + direction.

  When `neutral?: true`, returns centered canvas coords bit-identically and
  the precomputed direction for `nx/ny/nz`.
  """
  @spec sample(vec3(), map()) :: {float(), float(), vec3()}
  def sample(d, %{neutral?: true, center_x: cx, center_y: cy, x: x, y: y}) do
    {x - cx, y - cy, d}
  end

  def sample(d, params) do
    %{
      matrix: m,
      sigma: sigma,
      mobius_basis: basis,
      elev_rad: elev_rad,
      alpha: alpha
    } = params

    d = transform(m, d)
    d = dilate(d, sigma, basis)
    d = apply_elevation(d, elev_rad, alpha)
    {xs, ys} = to_chart(d, alpha)
    {xs, ys, d}
  end

  @spec identity() :: mat3()
  def identity, do: {1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}

  @spec norm(vec3()) :: float()
  def norm({x, y, z}), do: :math.sqrt(x * x + y * y + z * z)

  @spec dot(vec3(), vec3()) :: float()
  def dot({ax, ay, az}, {bx, by, bz}), do: ax * bx + ay * by + az * bz

  defp cross({ax, ay, az}, {bx, by, bz}) do
    {ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx}
  end

  defp normalize({x, y, z} = v) do
    n = norm(v)

    if n < @epsilon do
      {0.0, 0.0, 0.0}
    else
      {x / n, y / n, z / n}
    end
  end

  defp near_zero?({x, y, z}), do: abs(x) < @epsilon and abs(y) < @epsilon and abs(z) < @epsilon

  defp clamp(v, lo, _hi) when v < lo, do: lo
  defp clamp(v, _lo, hi) when v > hi, do: hi
  defp clamp(v, _lo, _hi), do: v
end
