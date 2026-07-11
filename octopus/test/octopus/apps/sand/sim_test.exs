defmodule Octopus.Apps.Sand.SimTest do
  use ExUnit.Case, async: true

  alias Octopus.Apps.Sand.Sim
  alias Octopus.Canvas

  @white {255, 255, 255}
  @red {255, 0, 0}

  defp sim(opts \\ []) do
    Sim.new(16, 8, Keyword.merge([supersample: 1, gravity: 0.0], opts))
  end

  describe "cell_empty?/2 ring wrap" do
    test "wraps x at boundaries" do
      sim = sim() |> Sim.put_cell({0, 0}, Sim.sand(@white))

      refute Sim.cell_empty?(sim, {0, 0})
      refute Sim.cell_empty?(sim, {16, 0})
      refute Sim.cell_empty?(sim, {-16, 0})
    end

    test "y below canvas is empty, y at or above height is solid" do
      sim = sim()

      assert Sim.cell_empty?(sim, {0, -1})
      refute Sim.cell_empty?(sim, {0, 8})
      refute Sim.cell_empty?(sim, {0, 100})
    end

    test "gap cells between panels are solid" do
      sim =
        Sim.new(34, 8,
          supersample: 1,
          gravity: 0.0,
          panel_led_ranges: [{0, 7}, {26, 33}]
        )

      refute Sim.cell_empty?(sim, {8, 0})
      refute Sim.cell_empty?(sim, {25, 4})
      assert Sim.cell_empty?(sim, {3, 0})
    end

    test "sand at panel edge cannot slide into gap" do
      sim =
        Sim.new(34, 8,
          supersample: 1,
          gravity: 0.0,
          panel_led_ranges: [{0, 7}, {26, 33}]
        )
        |> Sim.put_cell({7, 6}, Sim.sand(@white))
        |> Sim.put_cell({7, 7}, Sim.sand(@red))
        |> Sim.put_cell({6, 7}, Sim.sand(@red))

      sim = Sim.step(sim)

      refute Sim.get_cell(sim, {8, 7})
      assert Sim.get_cell(sim, {7, 6}) != nil
    end
  end

  describe "draw/2 downsampling" do
    test "averages S×S block into one LED pixel" do
      sim =
        Sim.new(4, 4, supersample: 4, gravity: 0.0)
        |> Sim.put_cell({5, 5}, Sim.sand(@red))

      canvas = Sim.draw(sim, Canvas.new(4, 4))
      assert Canvas.get_pixel(canvas, {1, 1}) == {15, 0, 0}
      assert Canvas.get_pixel(canvas, {0, 0}) == {0, 0, 0}
    end

    test "S=1 maps grains directly to LED pixels" do
      sim = sim() |> Sim.put_cell({3, 2}, Sim.sand(@red))
      canvas = Sim.draw(sim, Canvas.new(16, 8))
      assert Canvas.get_pixel(canvas, {3, 2}) == @red
    end
  end

  describe "step/1 bottom-up column fall" do
    test "stacked grains fall as a solid column without gaps" do
      sim =
        sim()
        |> Sim.put_cell({5, 0}, Sim.sand(@white))
        |> Sim.put_cell({5, 1}, Sim.sand(@white))

      sim = Sim.step(sim)

      assert Sim.get_cell(sim, {5, 0}) == nil
      assert Sim.get_cell(sim, {5, 1}) != nil
      assert Sim.get_cell(sim, {5, 2}) != nil
    end
  end

  describe "step/1 gravity" do
    test "accumulates vertical velocity while falling" do
      sim =
        Sim.new(8, 16, supersample: 1, gravity: 0.5)
        |> Sim.put_cell({4, 0}, Sim.sand(@white, 0.0))

      sim = Sim.step(sim)
      assert Sim.get_cell(sim, {4, 1}) == Sim.sand(@white, 0.5)

      sim = Sim.step(sim)
      assert Sim.get_cell(sim, {4, 2}) == Sim.sand(@white, 1.0)

      sim = Sim.step(sim)
      assert {:sand, @white, 1.5} = Sim.get_cell(sim, {4, 3})
    end

    test "caps velocity at v_max" do
      s = 4

      sim =
        Sim.new(8, 32, supersample: s, gravity: 10.0)
        |> Sim.put_cell({4, 0}, Sim.sand(@white, 0.0))

      sim =
        Enum.reduce(1..10, sim, fn _, sim ->
          Sim.step(sim)
        end)

      vy =
        sim.particles
        |> Map.values()
        |> List.first()
        |> then(fn {:sand, _, vy} -> vy end)

      assert vy <= Sim.default_v_max(s)
    end

    test "resets vy to 1.0 on landing" do
      sim =
        Sim.new(8, 8, supersample: 1, gravity: 0.5)
        |> Sim.put_cell({4, 6}, Sim.sand(@white, 2.0))

      sim = Sim.step(sim)
      assert Sim.get_cell(sim, {4, 7}) == Sim.sand(@white, 1.0)
    end

    test "S=1 with gravity=0 moves one cell per tick" do
      sim = sim(gravity: 0.0) |> Sim.put_cell({4, 2}, Sim.sand(@white))
      sim = Sim.step(sim)
      assert Sim.get_cell(sim, {4, 2}) == nil
      assert Sim.get_cell(sim, {4, 3}) == Sim.sand(@white, 0.0)
    end
  end

  describe "step/1 no double processing" do
    test "two adjacent grains each move exactly once per tick" do
      sim =
        sim()
        |> Sim.put_cell({5, 0}, Sim.sand(@white))
        |> Sim.put_cell({5, 1}, Sim.sand(@red))

      before = Map.keys(sim.particles) |> Enum.sort()
      sim = Sim.step(sim)
      after_keys = Map.keys(sim.particles) |> Enum.sort()

      assert before == [{5, 0}, {5, 1}]
      assert after_keys == [{5, 1}, {5, 2}]
      assert map_size(sim.particles) == 2
    end
  end

  describe "step/1 ring wrap slide" do
    test "grain slides diagonally through x wrap" do
      sim =
        sim()
        |> Sim.put_cell({0, 6}, Sim.sand(@white))
        |> Sim.put_cell({0, 7}, Sim.sand(@red))
        |> Sim.put_cell({1, 7}, Sim.sand(@red))

      sim = Sim.step(sim)

      assert Sim.get_cell(sim, {0, 6}) == nil
      assert Sim.get_cell(sim, {15, 7}) == Sim.sand(@white, 1.0)
    end
  end

  describe "step/1 particle-driven iteration" do
    test "only processes existing grains, not empty canvas area" do
      sim =
        sim()
        |> Sim.put_cell({2, 7}, Sim.sand(@white))

      sim = Sim.step(sim)
      assert map_size(sim.particles) == 1
    end
  end
end
