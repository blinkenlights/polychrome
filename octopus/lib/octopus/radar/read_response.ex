defmodule Octopus.Radar.ReadResponse do
  @moduledoc """
  Parser and config verifier for the AT+READ response from the HLK-LD6001A-60G.

  The device responds to `AT+READ` with a brace-delimited block of key-value
  pairs (one per line). The format is not valid JSON — string values such as
  firmware version tags are unquoted. Example:

      {
      "PeopleCntSoftVerison":NOP_1.07-02,
      "RangeRes":0.055664,
      "Range":450,
      "Sen":4,
      "detectionHeight":300,
      "XboundaryN":-450,
      "XboundaryP":450,
      "YboundaryN":-450,
      "YboundaryP":450,
      "Moving target":11.00,
      "Static target":10.00,
      "Target exit":0.50,
      }

  Timing values (`Moving target`, `Static target`, `Target exit`) are reported
  in **seconds** while the config stores **deciseconds** (1 s = 10 decisecs).
  """

  @type fields :: %{String.t() => String.t()}
  @type mismatch :: {atom(), integer(), integer()}

  @doc """
  Scan `buffer` for a complete AT+READ response block.

  Returns `{:ok, fields, remainder}` when the closing `}` has been received,
  or `{:pending, buffer}` while still accumulating.

  `fields` is a plain `%{string_key => string_value}` map (values are raw
  strings; callers are responsible for numeric conversion).
  """
  @spec parse(binary()) :: {:ok, fields(), binary()} | {:pending, binary()}
  def parse(buffer) when is_binary(buffer) do
    case find_block(buffer) do
      {:ok, block, remainder} -> {:ok, parse_block(block), remainder}
      :pending -> {:pending, buffer}
    end
  end

  @doc """
  Verify that the fields from an AT+READ response match the sensor config.

  Returns `:ok` when every checkable parameter matches, or
  `{:mismatch, [{config_key, expected_value, got_value}]}` listing every
  discrepancy.

  Timing fields (`Moving target`, `Static target`, `Target exit`) in the
  response are in seconds; the config values are in deciseconds. The
  comparison converts: `round(response_seconds × 10) == config_decisecs`.

  Missing fields in the response are silently ignored so that old firmware
  versions that lack some keys do not falsely trigger re-init.
  """
  @spec verify(fields(), keyword()) :: :ok | {:mismatch, [mismatch()]}
  def verify(fields, config) when is_map(fields) and is_list(config) do
    mismatches =
      [
        check_int(fields, "Sen", config, :sensitivity),
        check_int(fields, "Range", config, :range_cm),
        check_int(fields, "detectionHeight", config, :height_cm),
        check_int(fields, "XboundaryP", config, :x_pos_cm),
        check_int(fields, "XboundaryN", config, :x_neg_cm),
        check_int(fields, "YboundaryP", config, :y_pos_cm),
        check_int(fields, "YboundaryN", config, :y_neg_cm),
        check_decisecs(fields, "Moving target", config, :moving_decisecs),
        check_decisecs(fields, "Static target", config, :static_decisecs),
        check_decisecs(fields, "Target exit", config, :exit_decisecs)
      ]
      |> Enum.reject(&is_nil/1)

    case mismatches do
      [] -> :ok
      list -> {:mismatch, list}
    end
  end

  @doc """
  Extract the firmware version string from parsed fields.

  Returns `nil` when the field is absent.
  """
  @spec firmware_version(fields()) :: String.t() | nil
  def firmware_version(fields), do: Map.get(fields, "PeopleCntSoftVerison")

  ## Private

  # Find the opening `{` and closing `}`, return the block content and the
  # bytes that follow it. Tabs and carriage returns in the response are ignored
  # during line-level parsing so we only need to find the braces here.
  defp find_block(buffer) do
    with {open_pos, 1} <- :binary.match(buffer, "{"),
         rest_after_open = binary_part(buffer, open_pos + 1, byte_size(buffer) - open_pos - 1),
         {close_pos, 1} <- :binary.match(rest_after_open, "}") do
      block = binary_part(rest_after_open, 0, close_pos)
      remainder = binary_part(rest_after_open, close_pos + 1, byte_size(rest_after_open) - close_pos - 1)
      {:ok, block, remainder}
    else
      :nomatch -> :pending
    end
  end

  defp parse_block(block) do
    block
    |> String.split(["\n", "\r\n", "\r"])
    |> Enum.reduce(%{}, fn line, acc ->
      case parse_line(String.trim(line)) do
        {key, value} -> Map.put(acc, key, value)
        nil -> acc
      end
    end)
  end

  # Match `"KEY":VALUE,` or `"KEY":VALUE` — value may be unquoted
  defp parse_line(line) do
    case Regex.run(~r/^"([^"]+)":([^,]+),?$/, line) do
      [_, key, value] -> {key, String.trim(value)}
      _ -> nil
    end
  end

  defp check_int(fields, at_key, config, config_key) do
    with raw when not is_nil(raw) <- Map.get(fields, at_key),
         {got, _} <- Integer.parse(raw),
         expected <- Keyword.fetch!(config, config_key),
         false <- got == expected do
      {config_key, expected, got}
    else
      _ -> nil
    end
  end

  defp check_decisecs(fields, at_key, config, config_key) do
    with raw when not is_nil(raw) <- Map.get(fields, at_key),
         {got_f, _} <- Float.parse(raw),
         got_decisecs <- round(got_f * 10),
         expected <- Keyword.fetch!(config, config_key),
         false <- got_decisecs == expected do
      {config_key, expected, got_decisecs}
    else
      _ -> nil
    end
  end
end
