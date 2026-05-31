defmodule Octopus.Radar.Ack do
  @moduledoc """
  Scans a mixed binary/text UART receive buffer for HLK-LD6001A AT command
  responses during the `:configuring` phase.

  Unlike line-oriented parsing, this module finds `AT+OK` and
  `Save Para Fail` anywhere in the stream so acks are not lost when the
  device is still emitting binary tracking frames.
  """

  @max_buffer 4096

  @fail_pattern "Save Para Fail"
  @ok_pattern "AT+OK"

  @type result :: {:pending, binary()} | {:ok, binary()} | {:retry, binary()}

  @doc """
  Append `data` to `buffer` and scan for a command response.

  Returns `{:pending, remainder}` when no complete response is found yet,
  `{:ok, remainder}` on success, or `{:retry, remainder}` on persistence
  failure (`Save Para Fail`).
  """
  @spec feed(binary(), binary()) :: result()
  def feed(buffer, data) when is_binary(buffer) and is_binary(data) do
    buffer = buffer |> Kernel.<>(data) |> trim()

    case :binary.match(buffer, @fail_pattern) do
      {_, _} = match ->
        {:retry, consume_response(buffer, match)}

      :nomatch ->
        case :binary.match(buffer, @ok_pattern) do
          {_, _} = match -> {:ok, consume_response(buffer, match)}
          :nomatch -> {:pending, buffer}
        end
    end
  end

  defp consume_response(buffer, {start, length}) do
    suffix = binary_part(buffer, start, byte_size(buffer) - start)

    case :binary.match(suffix, "\n") do
      {offset, _} ->
        consumed = start + offset + 1
        binary_part(buffer, consumed, byte_size(buffer) - consumed)

      :nomatch ->
        skip_optional_crlf(buffer, start + length)
    end
  end

  defp skip_optional_crlf(buffer, pos) when pos >= byte_size(buffer), do: <<>>

  defp skip_optional_crlf(buffer, pos) do
    rest = binary_part(buffer, pos, byte_size(buffer) - pos)

    case rest do
      <<"\r\n", tail::binary>> -> tail
      <<"\r", tail::binary>> -> tail
      <<"\n", tail::binary>> -> tail
      other -> other
    end
  end

  defp trim(buffer) when byte_size(buffer) <= @max_buffer, do: buffer

  defp trim(buffer) do
    binary_part(buffer, byte_size(buffer) - @max_buffer, @max_buffer)
  end
end
