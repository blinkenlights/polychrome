defmodule Octopus.Sound.OSC do
  @moduledoc """
  Minimal OSC 1.0 encoder — messages and bundles with timetags.

  `oscx` handles the receiving side, but scheduling towards `scsynth` needs
  bundle timetags, which is the whole point of using SuperCollider: a bundle
  says *when* to execute, so scheduler jitter never reaches the audio.
  """

  # Seconds between the NTP epoch (1900-01-01) and the unix epoch.
  @ntp_epoch_offset 2_208_988_800
  @immediately <<0::size(32), 1::size(32)>>

  @type arg :: integer() | float() | binary()

  @doc "Encodes an OSC message, e.g. `message(\"/s_new\", [\"pc_ping\", 1000])`."
  @spec message(binary(), [arg()]) :: binary()
  def message(address, args \\ []) when is_binary(address) and is_list(args) do
    tags = "," <> Enum.map_join(args, &type_tag/1)
    payload = args |> Enum.map(&encode_arg/1) |> IO.iodata_to_binary()

    pad(address) <> pad(tags) <> payload
  end

  @doc "Bundle to be executed as soon as it arrives."
  @spec bundle([binary()]) :: binary()
  def bundle(messages) when is_list(messages) do
    "#bundle" <> <<0>> <> @immediately <> elements(messages)
  end

  @doc "Bundle to be executed at `unix_ms`, sample accurate on the server side."
  @spec bundle_at([binary()], integer()) :: binary()
  def bundle_at(messages, unix_ms) when is_list(messages) and is_integer(unix_ms) do
    "#bundle" <> <<0>> <> timetag(unix_ms) <> elements(messages)
  end

  @doc "NTP timetag for a unix timestamp in milliseconds."
  @spec timetag(integer()) :: binary()
  def timetag(unix_ms) do
    seconds = div(unix_ms, 1000) + @ntp_epoch_offset
    fraction = round(rem(unix_ms, 1000) / 1000 * 4_294_967_296)

    # A full second of fraction would overflow into the next second.
    case fraction do
      4_294_967_296 -> <<seconds + 1::size(32), 0::size(32)>>
      fraction -> <<seconds::size(32), fraction::size(32)>>
    end
  end

  defp elements(messages) do
    Enum.map_join(messages, fn element -> <<byte_size(element)::size(32)>> <> element end)
  end

  defp type_tag(value) when is_integer(value), do: "i"
  defp type_tag(value) when is_float(value), do: "f"
  defp type_tag(value) when is_binary(value), do: "s"

  defp encode_arg(value) when is_integer(value), do: <<value::signed-size(32)>>
  defp encode_arg(value) when is_float(value), do: <<value::float-size(32)>>
  defp encode_arg(value) when is_binary(value), do: pad(value)

  # OSC strings are null terminated and padded to a multiple of four bytes.
  defp pad(string) do
    terminated = string <> <<0>>
    padding = rem(4 - rem(byte_size(terminated), 4), 4)
    terminated <> :binary.copy(<<0>>, padding)
  end
end
