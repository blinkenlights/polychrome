defmodule Octopus.Apps.Sphere do
  use Octopus.App, category: :interactive
  use Octopus.Params, prefix: :sphere
  alias Octopus.Canvas
  alias Octopus.Installation
  alias Octopus.Image

  def name, do: "Sphere"

  def compatible? do
    Octopus.Installation.arrangement() == :circular
  end

  def app_init(_) do
    Octopus.App.configure_display(layout: :adjacent_panels)
    equirectangular_image = Image.load("equirectangular")
    :timer.send_interval(16, :tick)
    {:ok, %{image: equirectangular_image, rotation: 0.0}}
  end

  def handle_info(:tick, state) do
    dt = 0.016
    speed = param(:rotate_speed, 0.2)
    state = %{state | rotation: state.rotation + speed * dt}
    canvas = draw(state)
    Octopus.App.update_display(canvas, :rgb, easing_interval: 0)
    {:noreply, state}
  end

  def draw(state) do
    panel_w = Installation.panel_width()
    panel_h = Installation.panel_height()

    Installation.virtual_pixel_positions_per_panel()
    |> Enum.map(fn panel ->
      for {{x, y}, i} <- Enum.with_index(panel),
          into: Canvas.new(panel_w, panel_h) do
        local_x = rem(i, panel_w)
        local_y = div(i, panel_w)

        {ix, iy} =
          {x, y}
          |> to_sphere_coordinates(state.rotation)
          |> to_pixel_coordinates(state.image)

        color = Canvas.get_pixel(state.image, {ix, iy})

        {{local_x, local_y}, color}
      end
    end)
    |> Enum.reduce(&Canvas.join(&2, &1))
  end

  defp to_sphere_coordinates({x, y}, rotation) do
    width = Installation.width()
    height = Installation.height()

    nx = (x + 0.5) / width * 2.0 - 1.0
    ny = 1.0 - (y + 0.5) / height * 2.0

    fov_v_deg = param(:fov_vertical_deg, 60.0)
    fov_h_deg_param = param(:fov_horizontal_deg, nil)

    fov_v = fov_v_deg * :math.pi() / 180.0
    aspect = width / height

    fov_h =
      case fov_h_deg_param do
        nil -> 2.0 * :math.atan(:math.tan(fov_v / 2.0) * aspect)
        deg -> deg * :math.pi() / 180.0
      end

    yaw_deg = param(:yaw_deg, 0.0)
    pitch_deg = param(:pitch_deg, 0.0)
    roll_deg = param(:roll_deg, 0.0)

    yaw = yaw_deg * :math.pi() / 180.0 + rotation
    pitch = pitch_deg * :math.pi() / 180.0
    roll = roll_deg * :math.pi() / 180.0

    q_cam =
      q_mul(
        q_from_axis_angle({0.0, 1.0, 0.0}, yaw),
        q_mul(q_from_axis_angle({1.0, 0.0, 0.0}, pitch), q_from_axis_angle({0.0, 0.0, 1.0}, roll))
      )

    alpha = nx * (fov_h / 2.0)
    beta = ny * (fov_v / 2.0)

    q_offset =
      q_mul(
        q_from_axis_angle({0.0, 1.0, 0.0}, alpha),
        q_from_axis_angle({1.0, 0.0, 0.0}, beta)
      )

    {cx, cy, cz} = q_rotate_vec(q_offset, {0.0, 0.0, 1.0})
    {rx, ry, rz} = q_rotate_vec(q_cam, {cx, cy, cz})

    lon = :math.atan2(rx, rz)
    lat = :math.asin(ry |> clamp(-1.0, 1.0))

    {lon, lat}
  end

  defp clamp(value, min_v, max_v) do
    value |> max(min_v) |> min(max_v)
  end

  defp to_pixel_coordinates({lon, lat}, %Canvas{width: img_w, height: img_h}) do
    u = (lon + :math.pi()) / (2.0 * :math.pi())
    v = (:math.pi() / 2.0 - lat) / :math.pi()

    # wrap horizontally, clamp vertically
    xi = Integer.mod(trunc(u * img_w), img_w)

    yi =
      v
      |> max(0.0)
      |> min(1.0)
      |> (fn vv -> min(trunc(vv * img_h), img_h - 1) end).()

    {xi, yi}
  end

  defp q_from_axis_angle({ax, ay, az}, theta) do
    half = theta / 2.0
    s = :math.sin(half)
    w = :math.cos(half)
    {w, ax * s, ay * s, az * s}
  end

  defp q_mul({w1, x1, y1, z1}, {w2, x2, y2, z2}) do
    {
      w1 * w2 - x1 * x2 - y1 * y2 - z1 * z2,
      w1 * x2 + x1 * w2 + y1 * z2 - z1 * y2,
      w1 * y2 - x1 * z2 + y1 * w2 + z1 * x2,
      w1 * z2 + x1 * y2 - y1 * x2 + z1 * w2
    }
  end

  defp q_conj({w, x, y, z}), do: {w, -x, -y, -z}

  defp q_rotate_vec(q = {qw, qx, qy, qz}, {vx, vy, vz}) do
    # q * v * q_conj
    vq = {0.0, vx, vy, vz}
    {rw, rx, ry, rz} = q_mul(q_mul(q, vq), q_conj(q))
    {_w, x, y, z} = {rw, rx, ry, rz}
    {x, y, z}
  end
end
