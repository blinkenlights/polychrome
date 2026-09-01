defmodule Octopus.Sound.PatchTest do
  use ExUnit.Case, async: false

  alias Octopus.Sound.{Patch, Pattern}

  setup do
    start_supervised!(Patch)
    Patch.subscribe()
    on_exit(fn -> Phoenix.PubSub.unsubscribe(Octopus.PubSub, "sound_patch") end)
    :ok
  end

  test "starts on A with an empty grid" do
    assert Patch.slot() == :a
    assert Pattern.empty?(Patch.pattern())
  end

  test "an edit is announced, so every open tab follows" do
    Patch.update(&Pattern.put_step(&1, 1, 0, 4))

    assert_receive {:sound_patch, %{pattern: pattern, slot: :a}}
    assert [%{channel: 4}] = Pattern.notes_for(pattern, 0)
  end

  test "A and B are kept apart — that is the point of comparing them" do
    Patch.update(&Pattern.put_step(&1, 1, 0, 4))
    Patch.switch()

    assert Patch.slot() == :b
    assert Pattern.empty?(Patch.pattern())

    Patch.update(&Pattern.put_step(&1, 1, 0, 9))
    Patch.switch()

    assert [%{channel: 4}] = Patch.pattern() |> Pattern.notes_for(0)
  end

  test "copying to the other side gives a comparison a common starting point" do
    Patch.update(&Pattern.put_step(&1, 1, 0, 4))
    Patch.copy_to_other()
    Patch.switch()

    assert [%{channel: 4}] = Patch.pattern() |> Pattern.notes_for(0)
  end

  test "put replaces the live pattern wholesale, as loading a composition does" do
    Patch.put(Pattern.new() |> Pattern.put_step(2, 3, 7))

    assert [%{channel: 7}] = Patch.pattern() |> Pattern.notes_for(3)
  end
end
