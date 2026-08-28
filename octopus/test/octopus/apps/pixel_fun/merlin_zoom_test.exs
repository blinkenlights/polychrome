defmodule Octopus.Apps.PixelFun.MerlinZoomTest do
  use ExUnit.Case, async: true

  import :math, only: [sqrt: 1]

  alias Octopus.Apps.PixelFun.MerlinZoom

  @eps 1.0e-5

  defp assert_vec({ax, ay, az}, {bx, by, bz}) do
    assert_in_delta ax, bx, @eps
    assert_in_delta ay, by, @eps
    assert_in_delta az, bz, @eps
  end

  defp normalize({x, y, z}) do
    n = sqrt(x * x + y * y + z * z)
    {x / n, y / n, z / n}
  end

  defp norm({x, y, z}), do: :math.sqrt(x * x + y * y + z * z)

  @nordpol {0.0, 0.0, 1.0}
  @suedpol {0.0, 0.0, -1.0}
  @aequator {1.0, 0.0, 0.0}

  describe "Fixpunkte" do
    test "das Zentrum bleibt unveraendert" do
      assert_vec(MerlinZoom.zoom(@nordpol, @nordpol, 0.25), @nordpol)
    end

    test "die Antipode bleibt unveraendert" do
      assert_vec(MerlinZoom.zoom(@suedpol, @nordpol, 0.25), @suedpol)
    end

    test "Fixpunkte gelten fuer beliebiges Zentrum" do
      x0 = normalize({0.3, -0.5, 0.8})
      antipode = normalize({-0.3, 0.5, -0.8})
      assert_vec(MerlinZoom.zoom(x0, x0, 0.4), x0)
      assert_vec(MerlinZoom.zoom(antipode, x0, 0.4), antipode)
    end
  end

  describe "bekannte Stauchungen (Zentrum = Nordpol)" do
    test "Aequatorpunkt, starke Stauchung k=0.25" do
      assert_vec(MerlinZoom.zoom(@aequator, @nordpol, 0.25), {0.470588, 0.0, 0.882353})
    end

    test "Aequatorpunkt, mittlere Stauchung k=0.5" do
      assert_vec(MerlinZoom.zoom(@aequator, @nordpol, 0.5), {0.800000, 0.0, 0.600000})
    end

    test "Aequatorpunkt, schwache Stauchung k=0.9" do
      assert_vec(MerlinZoom.zoom(@aequator, @nordpol, 0.9), {0.994475, 0.0, 0.104972})
    end

    test "Punkt bei theta=60 Grad, k=0.25" do
      p60 = {:math.sin(:math.pi() / 3), 0.0, :math.cos(:math.pi() / 3)}
      assert_vec(MerlinZoom.zoom(p60, @nordpol, 0.25), {0.282784, 0.0, 0.959184})
    end
  end

  describe "beliebiges Zentrum" do
    test "beliebiger Punkt und beliebiges Zentrum, k=0.4" do
      x = normalize({1.0, 1.0, 0.0})
      x0 = normalize({0.3, -0.5, 0.8})
      assert_vec(MerlinZoom.zoom(x, x0, 0.4), {0.773710, 0.160958, 0.612752})
    end
  end

  describe "Invarianten" do
    test "die Ausgabe ist stets ein Einheitsvektor" do
      x0 = normalize({0.2, 0.7, -0.3})

      for _ <- 1..1000 do
        x = normalize({:rand.normal(), :rand.normal(), :rand.normal()})
        result = MerlinZoom.zoom(x, x0, 0.3)
        assert_in_delta norm(result), 1.0, @eps
      end
    end

    test "k naeher an 1 bewegt den Punkt weniger als kleineres k" do
      dist = fn k ->
        {rx, ry, rz} = MerlinZoom.zoom(@aequator, @nordpol, k)
        {ax, ay, az} = @aequator
        dot = rx * ax + ry * ay + rz * az
        :math.acos(max(-1.0, min(1.0, dot)))
      end

      assert dist.(0.25) > dist.(0.5)
      assert dist.(0.5) > dist.(0.9)
    end

    test "die Stauchung zieht Aequatorpunkte Richtung Zentrum (z steigt)" do
      {_x, _y, z} = MerlinZoom.zoom(@aequator, @nordpol, 0.25)
      assert z > 0.0
    end
  end

  describe "Guard" do
    test "k <= 0.0 wird abgewiesen" do
      assert_raise FunctionClauseError, fn ->
        MerlinZoom.zoom(@aequator, @nordpol, 0.0)
      end

      assert_raise FunctionClauseError, fn ->
        MerlinZoom.zoom(@aequator, @nordpol, -1.0)
      end
    end
  end

  describe "Identitaet" do
    test "k = 1.0 laesst den Punkt unveraendert" do
      assert_vec(MerlinZoom.zoom(@aequator, @nordpol, 1.0), @aequator)
    end
  end

  describe "spherical overload" do
    test "phi liegt in [0, 2*pi)" do
      for _ <- 1..1000 do
        x = normalize({:rand.normal(), :rand.normal(), :rand.normal()})
        {_theta, phi} = MerlinZoom.zoom(MerlinZoom.spherical(x), {0.5, 1.0}, 0.3)
        assert phi >= 0.0
        assert phi < 2 * :math.pi()
      end
    end
  end
end
