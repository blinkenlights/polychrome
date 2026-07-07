defmodule Octopus.Apps.PixelFun.FormulaPresetsTest do
  use Octopus.DataCase, async: true

  alias Octopus.Apps.PixelFun.FormulaPresets

  describe "builtins/0" do
    test "returns presets with valid formulas" do
      presets = FormulaPresets.builtins()

      assert length(presets) >= 6

      for preset <- presets do
        assert preset.builtin
        assert String.starts_with?(preset.id, "builtin:")
        assert is_binary(preset.name)
        assert FormulaPresets.validate_formula(preset.formula) == :ok
      end
    end
  end

  describe "list_all/0" do
    test "includes builtins and user presets" do
      assert {:ok, _} =
               FormulaPresets.create(%{
                 name: "My wave",
                 formula: "sin(x+t)"
               })

      ids = FormulaPresets.list_all() |> Enum.map(& &1.id)

      assert "builtin:classic_ripple" in ids
      assert Enum.any?(ids, &String.starts_with?(&1, "user:"))
    end
  end

  describe "get/1" do
    test "finds builtin and user presets" do
      assert %{name: "Classic ripple"} = FormulaPresets.get("builtin:classic_ripple")

      {:ok, %{id: id}} =
        FormulaPresets.create(%{name: "Test preset", formula: "cos(y-t)"})

      assert FormulaPresets.get(id) != nil
      assert FormulaPresets.get("user:999999") == nil
    end
  end

  describe "create/1" do
    test "rejects invalid formulas" do
      assert {:error, changeset} =
               FormulaPresets.create(%{name: "Bad", formula: "sin(+"})

      assert "has invalid syntax" in errors_on(changeset).formula
    end

    test "rejects duplicate names" do
      attrs = %{name: "Unique wave", formula: "sin(t)"}

      assert {:ok, _} = FormulaPresets.create(attrs)

      assert {:error, changeset} = FormulaPresets.create(attrs)
      assert "has already been taken" in errors_on(changeset).name
    end
  end

  describe "delete/1" do
    test "deletes user presets but not builtins" do
      {:ok, %{id: id}} =
        FormulaPresets.create(%{name: "Disposable", formula: "sin(x)"})

      assert :ok = FormulaPresets.delete(id)
      assert FormulaPresets.get(id) == nil
      assert {:error, :builtin} = FormulaPresets.delete("builtin:cross_waves")
    end
  end

  describe "id_for_formula/1" do
    test "returns preset id or custom" do
      assert "builtin:classic_ripple" =
               FormulaPresets.id_for_formula("sin(10*t-hypot(x,y))")

      assert "custom" = FormulaPresets.id_for_formula("sin(x+t*99)")
    end
  end

  describe "user_formula_exists?/1" do
    test "detects saved user formulas only" do
      refute FormulaPresets.user_formula_exists?("sin(x+t*99)")

      assert {:ok, _} =
               FormulaPresets.create(%{name: "Saved", formula: "cos(x-y+t)"})

      assert FormulaPresets.user_formula_exists?("cos(x-y+t)")
      refute FormulaPresets.user_formula_exists?("sin(10*t-hypot(x,y))")
    end
  end

  describe "validate_formula/1" do
    test "accepts valid and rejects invalid input" do
      assert :ok = FormulaPresets.validate_formula("sin(x+y+t)")
      assert :error = FormulaPresets.validate_formula("(((")
    end
  end
end
