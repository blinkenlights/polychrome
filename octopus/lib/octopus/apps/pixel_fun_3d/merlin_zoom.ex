defmodule Octopus.Apps.PixelFun3d.MerlinZoom do
  import :math, only: [sqrt: 1, sin: 1, cos: 1, acos: 1, atan2: 2, pi: 0]

  def zoom({theta, phi}, {theta0, phi0}, k) do
    zoom(cartesian({theta, phi}), cartesian({theta0, phi0}), k) |> spherical()
  end

  @doc """
  Wendet einen zoom mit zentrum x0 auf x an
  x und x0 sollten dabei einheitslänge haben, dh
  $$\|x\|_2=\|x0\|_2=1$$
  """
  def zoom(x, x0, k) when 0 < k do
    c = dot(x, x0) |> clamp(-1, 1)
    angle = acos(c)

    angle_neu = 2.0 * atan2(k * sin(angle / 2), cos(angle / 2))

    perp = sub(x, scale(x0, c))
    nrm = norm(perp)
    u = if nrm > 1.0e-12, do: scale(perp, 1.0 / nrm), else: {0.0, 0.0, 0.0}

    q = add(scale(x0, cos(angle_neu)), scale(u, sin(angle_neu)))
    scale(q, 1.0 / norm(q))
  end

  defp dot({a1, a2, a3}, {b1, b2, b3}), do: a1*b1+a2*b2+a3*b3
  defp sub({a1, a2, a3}, {b1, b2, b3}), do: {a1-b1, a2-b2, a3-b3}
  defp add({a1, a2, a3}, {b1, b2, b3}), do: {a1+b1, a2+b2, a3+b3}
  defp scale({a1, a2, a3}, s), do: {a1*s, a2*s, a3*s}
  defp norm(v), do: sqrt(dot(v,v)) # 2 Norm des R^2
  defp clamp(v, lo, hi), do: v |> max(lo) |> min(hi)

  defp cartesian({theta, phi}) do
    {
      sin(theta) * cos(phi),
      sin(theta) * sin(phi),
      cos(theta)
    }
  end

  defp spherical({x, y, z}) do
    theta = acos(clamp(z, -1.0, 1.0))
    phi = :math.fmod(atan2(y, x) + 2 * pi(), 2 * pi())
    {theta, phi}
  end
end
