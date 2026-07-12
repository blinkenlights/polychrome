defmodule Octopus.SphereTest do
  use ExUnit.Case, async: true

  alias Octopus.Sphere

  defp assert_unit({x, y, z}, eps \\ 1.0e-12) do
    assert_in_delta Sphere.norm({x, y, z}), 1.0, eps
  end

  describe "direction / to_chart round trip" do
    test "chart(direction(x,y)) == {x-cx, y-cy} within 1e-9 for visible band" do
      w = 312
      h = 8
      cx = w / 2 - 0.5
      cy = h / 2 - 0.5
      alpha = Sphere.alpha(w)

      for x <- 0..(w - 1), y <- 0..(h - 1), rem(x, 26) < 8 do
        d = Sphere.direction(x, y, w, h)
        {xs, ys} = Sphere.to_chart(d, alpha)
        assert_in_delta xs, x - cx, 1.0e-9
        assert_in_delta ys, y - cy, 1.0e-9
      end
    end
  end

  describe "rotation" do
    test "|M·d| == 1 within 1e-12 for random rotations/directions" do
      for _ <- 1..40 do
        yaw = :rand.uniform() * :math.pi() * 2
        roll = (:rand.uniform() - 0.5) * :math.pi()
        tilt = (:rand.uniform() - 0.5) * 0.5
        t = :rand.uniform() * 10

        m =
          Sphere.orientation(
            yaw: yaw,
            roll_angle: roll,
            roll_pivot_phi: :rand.uniform() * :math.pi() * 2,
            tilt_amplitude: tilt,
            tilt_speed: 0.5,
            tilt_mode: :wobble,
            t: t
          )

        d =
          Sphere.direction(
            :rand.uniform() * 312,
            :rand.uniform() * 8,
            312,
            8
          )

        assert_unit(Sphere.transform(m, d))
      end
    end

    test "composition order: yaw-then-tilt differs from tilt-then-yaw" do
      yaw = 0.7
      tilt = 0.4
      d = Sphere.direction(50, 3, 312, 8)

      m_prompt =
        Sphere.orientation(
          yaw: yaw,
          tilt_amplitude: tilt,
          tilt_speed: 0.0,
          tilt_mode: :wobble,
          t: 0.0
        )

      m_swapped = Sphere.mul(Sphere.rot_axis({1.0, 0.0, 0.0}, tilt), Sphere.rot_z(yaw))

      a = Sphere.transform(m_prompt, d)
      b = Sphere.transform(m_swapped, d)

      refute abs(elem(a, 0) - elem(b, 0)) < 1.0e-9 and abs(elem(a, 1) - elem(b, 1)) < 1.0e-9 and
               abs(elem(a, 2) - elem(b, 2)) < 1.0e-9
    end
  end

  describe "Möbius" do
    test "sigma=0 is identity within 1e-12" do
      basis = Sphere.mobius_basis(0.5)
      d = Sphere.direction(100, 4, 312, 8)
      out = Sphere.dilate(d, 0.0, basis)
      assert_in_delta elem(out, 0), elem(d, 0), 1.0e-12
      assert_in_delta elem(out, 1), elem(d, 1), 1.0e-12
      assert_in_delta elem(out, 2), elem(d, 2), 1.0e-12
    end

    test "fixed points a and -a; norm preserved" do
      phi = 1.2
      basis = Sphere.mobius_basis(phi)
      {_u, _v, a} = basis
      {ax, ay, az} = a
      neg_a = {-ax, -ay, -az}

      assert Sphere.dilate(a, 0.8, basis) == a
      assert Sphere.dilate(neg_a, 0.8, basis) == neg_a

      d = Sphere.direction(80, 2, 312, 8)
      assert_unit(Sphere.dilate(d, 0.5, basis))
    end

    test "conformality smoke: stereographic dilation preserves plane angles" do
      basis = Sphere.mobius_basis(0.0)
      {_u, _v, a} = basis
      {ax, ay, az} = a

      project = fn {dx, dy, dz} ->
        den = 1.0 + dx * ax + dy * ay + dz * az
        {{ux, uy, uz}, {vx, vy, vz}, _} = basis
        {(dx * ux + dy * uy + dz * uz) / den, (dx * vx + dy * vy + dz * vz) / den}
      end

      d0 = Sphere.direction(40, 3, 312, 8)
      d1 = Sphere.direction(40.2, 3, 312, 8)
      d2 = Sphere.direction(40, 3.2, 312, 8)

      {x0, y0} = project.(d0)
      {x1, y1} = project.(d1)
      {x2, y2} = project.(d2)

      angle = fn {ax, ay}, {bx, by} ->
        :math.atan2(ax * by - ay * bx, ax * bx + ay * by)
      end

      before = angle.({x1 - x0, y1 - y0}, {x2 - x0, y2 - y0})

      sigma = 0.5
      o0 = Sphere.dilate(d0, sigma, basis)
      o1 = Sphere.dilate(d1, sigma, basis)
      o2 = Sphere.dilate(d2, sigma, basis)

      {px0, py0} = project.(o0)
      {px1, py1} = project.(o1)
      {px2, py2} = project.(o2)
      after_ang = angle.({px1 - px0, py1 - py0}, {px2 - px0, py2 - py0})

      assert_in_delta before, after_ang, 1.0e-6
    end
  end
end
