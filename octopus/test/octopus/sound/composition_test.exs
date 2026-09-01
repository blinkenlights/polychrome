defmodule Octopus.Sound.CompositionTest do
  use Octopus.DataCase, async: false

  alias Octopus.Sound.{Composition, Patch, Pattern}

  setup do
    start_supervised!(Patch)
    :ok
  end

  defp pattern do
    Pattern.new()
    |> Pattern.put_step(1, 0, 3)
    |> Pattern.put_step(2, 8, 11)
  end

  test "a saved composition survives and comes back as the same pattern" do
    {:ok, saved} = Composition.save("Ring-Chase 3", pattern(), bpm: 96.0, scene: "sin(x)")

    assert saved.bpm == 96.0
    assert saved.scene == "sin(x)"

    # Reloading from the database, not from memory — this is the milestone.
    {:ok, loaded} = Composition.load(saved.id)

    assert loaded.name == "Ring-Chase 3"
    assert [%{channel: 3}] = Patch.pattern() |> Pattern.notes_for(0)
    assert [%{channel: 11}] = Patch.pattern() |> Pattern.notes_for(8)
  end

  test "saving the same name again overwrites instead of piling up" do
    {:ok, first} = Composition.save("Drone", pattern())
    {:ok, second} = Composition.save("Drone", Pattern.new() |> Pattern.put_step(1, 1, 2))

    assert first.id == second.id
    assert length(Composition.list()) == 1
  end

  test "a take keeps the moment under its own name" do
    Composition.save("Arbeitsversion", pattern())
    {:ok, take} = Composition.take(pattern())

    assert take.name =~ ~r/^Take \d{4}-\d{2}-\d{2}/
    assert length(Composition.list()) == 2
  end

  test "a name is required" do
    assert {:error, changeset} = Composition.save("", pattern())
    assert "can't be blank" in errors_on(changeset).name
  end

  test "loading something that is gone reports it instead of raising" do
    assert Composition.load(-1) == :error
  end

  test "delete removes it from the list" do
    {:ok, saved} = Composition.save("Weg damit", pattern())
    Composition.delete(saved.id)

    assert Composition.list() == []
  end
end
