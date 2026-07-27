defmodule Octopus.Osc.SoftTakeoverTest do
  use ExUnit.Case, async: false

  alias Octopus.Osc.SoftTakeover

  @client {:test, 1}

  setup do
    case Process.whereis(SoftTakeover) do
      nil -> start_supervised!(SoftTakeover)
      _ -> :ok
    end

    SoftTakeover.reset!()
    :ok
  end

  test "rejects distant values until pickup, then accepts" do
    refute SoftTakeover.accept?(@client, :zoom_base, 5.0, 1.0)
    refute SoftTakeover.matched?(@client, :zoom_base)

    assert SoftTakeover.accept?(@client, :zoom_base, 1.02, 1.0)
    assert SoftTakeover.matched?(@client, :zoom_base)
    assert SoftTakeover.accept?(@client, :zoom_base, 5.0, 1.0)
  end

  test "mark_matched_many arms a client for the performance bank" do
    SoftTakeover.mark_matched_many(@client, [:zoom_base, :global_speed])
    assert SoftTakeover.accept?(@client, :zoom_base, 9.0, 1.0)
    assert SoftTakeover.accept?(@client, :global_speed, 3.0, 1.0)
  end
end
