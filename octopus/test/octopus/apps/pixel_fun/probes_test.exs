defmodule Octopus.Apps.PixelFun.ProbesTest do
  use ExUnit.Case, async: false

  alias Octopus.Apps.PixelFun.{Program, State}
  alias Octopus.Installation
  alias Octopus.Sound.Probes

  @pixel_fun Module.concat(["Octopus", "Apps", "PixelFun"])

  setup do
    original = Application.get_env(:octopus, :installation)
    on_exit(fn -> Application.put_env(:octopus, :installation, original) end)
    :ok
  end

  defp with_installation(installation, fun) do
    Application.put_env(:octopus, :installation, installation)
    fun.()
  end

  defp state(formula, overrides \\ []) do
    {:ok, program} = Program.parse(formula)

    fields =
      Keyword.merge(
        [
          program: program,
          display_info: %{width: Installation.width(), height: Installation.height()},
          colors: {Chameleon.HSV.new(0, 70, 100), Chameleon.HSV.new(180, 70, 100)},
          seconds: 0.0,
          orbit_rate: 0.0,
          roll_rate: 0.0,
          zoom_base: 1.0,
          panel_interaction_factors: %{},
          audio_input: %{low: 0.0, mid: 0.0, high: 0.0}
        ],
        overrides
      )

    struct!(State, fields)
  end

  defp probe_values(state), do: apply(@pixel_fun, :probe_values, [state])

  describe "on the ring" do
    test "one value per panel" do
      with_installation(Octopus.Installation.Nation2026, fn ->
        values = probe_values(state("sin(x*0.5 - t)"))

        assert length(values) == Installation.num_panels()
        assert Enum.all?(values, &is_float/1)
      end)
    end

    test "values stay inside the formula range" do
      with_installation(Octopus.Installation.Nation2026, fn ->
        for formula <- ["sin(x*0.5 - t)", "x*100", "0-99"] do
          assert Enum.all?(probe_values(state(formula)), &(&1 >= -1.0 and &1 <= 1.0))
        end
      end)
    end

    test "a constant formula reads the same everywhere" do
      with_installation(Octopus.Installation.Nation2026, fn ->
        assert probe_values(state("1")) |> Enum.uniq() == [1.0]
      end)
    end

    test "a formula that varies with position reads differently per panel" do
      with_installation(Octopus.Installation.Nation2026, fn ->
        values = probe_values(state("sin(x*0.5)"))

        assert length(Enum.uniq(values)) > 1
      end)
    end

    test "the wave moves on as time passes — this is what makes it a chase" do
      with_installation(Octopus.Installation.Nation2026, fn ->
        at_zero = probe_values(state("sin(x*0.5 - t)", seconds: 0.0))
        later = probe_values(state("sin(x*0.5 - t)", seconds: 0.7))

        assert at_zero != later
      end)
    end
  end

  describe "on a wall" do
    test "one value per panel there too" do
      with_installation(Octopus.Installation.Woodstock2, fn ->
        values = probe_values(state("sin(x*0.3 + t)"))

        assert length(values) == Installation.num_panels()
        assert Enum.all?(values, &(&1 >= -1.0 and &1 <= 1.0))
      end)
    end
  end

  describe "center_pixel_index/0" do
    test "points at the middle of a panel" do
      with_installation(Octopus.Installation.Nation2026, fn ->
        # 8x8 panels, row-major: row 4, column 4.
        assert Probes.center_pixel_index() == 36
      end)
    end
  end

  describe "broadcast/2" do
    test "reaches subscribers with the frame's values" do
      Probes.subscribe()
      on_exit(&Probes.unsubscribe/0)

      Probes.broadcast([0.1, -0.2], 1.5)

      assert_receive {:pixel_probes, %{values: [0.1, -0.2], seconds: 1.5, at_ms: at_ms}}
      assert is_integer(at_ms)
    end
  end
end
