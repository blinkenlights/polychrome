defmodule Octopus.Sound.Time do
  @moduledoc """
  One time base for the sound stack.

  Musical math runs on monotonic milliseconds so a clock adjustment can never
  make the transport jump. Engines that schedule ahead need wall clock time
  (OSC timetags are NTP timestamps), so both are read together whenever one is
  converted into the other.
  """

  @doc "Monotonic milliseconds. The unit every timestamp in this stack uses."
  @spec now() :: integer()
  def now, do: System.monotonic_time(:millisecond)

  @doc """
  Converts a monotonic timestamp to unix milliseconds.

  The offset between the two clocks is read fresh every time rather than
  cached: the system clock is nudged by NTP while we run, and a cached offset
  would slowly hand the sound engine timestamps that no longer mean what they
  say. Two system calls are cheaper than that class of bug.
  """
  @spec to_unix(integer()) :: integer()
  def to_unix(mono_ms) do
    mono_ms + (System.system_time(:millisecond) - System.monotonic_time(:millisecond))
  end
end
