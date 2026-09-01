defmodule Octopus.Sound.Time do
  @moduledoc """
  One time base for the sound stack.

  Musical math runs on monotonic milliseconds so a clock adjustment can never
  make the transport jump. Engines that schedule ahead need wall clock time
  (OSC timetags are NTP timestamps), so the offset between both is captured
  once and reused.
  """

  @offset_key {__MODULE__, :offset}

  @doc "Monotonic milliseconds. The unit every timestamp in this stack uses."
  @spec now() :: integer()
  def now, do: System.monotonic_time(:millisecond)

  @doc "Converts a monotonic timestamp to unix milliseconds."
  @spec to_unix(integer()) :: integer()
  def to_unix(mono_ms), do: mono_ms + offset()

  defp offset do
    case :persistent_term.get(@offset_key, nil) do
      nil ->
        offset = System.system_time(:millisecond) - System.monotonic_time(:millisecond)
        :persistent_term.put(@offset_key, offset)
        offset

      offset ->
        offset
    end
  end
end
