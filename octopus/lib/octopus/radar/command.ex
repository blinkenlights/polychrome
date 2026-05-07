defmodule Octopus.Radar.Command do
  @moduledoc """
  AT command construction and response classification for the
  HLK-LD6001A-60G.

  All commands are ASCII text terminated by a newline (manual §6, §9).
  Successful commands respond with `AT+OK\r\n` (control commands) or
  `AT+OK=<value>\r\n` (parameter-setting commands). Failed-to-store
  responses return `Save Para Fail` (manual §8.3) and the same command
  should be retransmitted. Unknown commands return `AT+ERR\r\n`.

  The startup sequence implemented here follows the recommendation from
  manual §8.2: stop the device, switch to detailed binary protocol mode
  (`DEBUG=3`), apply geometry and disappearance-timing parameters, then
  start operation.

  ### Command-spelling note (firmware NOP_1.07-02)

  Manual §9.3 lists the four detection-zone boundary commands as
  `AT+XPosiD`, `AT+XNegaD`, `AT+YPosiD`, `AT+YNegaD` (with a trailing
  `D`). On real firmware those spellings return `AT+ERR`; the actually
  accepted spellings are `AT+XPosi`, `AT+XNega`, `AT+YPosi`, `AT+YNega`
  (no `D`). This was verified against a `NOP_1.07-02` unit. We use the
  spellings the device accepts.
  """

  @typedoc "A merged sensor configuration (defaults overlaid with per-sensor overrides)."
  @type sensor_config :: keyword()

  @doc """
  Build the ordered list of AT command lines (each already newline-terminated)
  to send during the `:configuring` phase, derived from `config`.
  """
  @spec init_sequence(sensor_config()) :: [String.t()]
  def init_sequence(config) do
    [
      "AT+STOP",
      "AT+DEBUG=3",
      "AT+HEIGHTD=#{Keyword.fetch!(config, :height_cm)}",
      "AT+RANGE=#{Keyword.fetch!(config, :range_cm)}",
      "AT+XPosi=#{Keyword.fetch!(config, :x_pos_cm)}",
      "AT+XNega=#{Keyword.fetch!(config, :x_neg_cm)}",
      "AT+YPosi=#{Keyword.fetch!(config, :y_pos_cm)}",
      "AT+YNega=#{Keyword.fetch!(config, :y_neg_cm)}",
      "AT+Moving=#{Keyword.fetch!(config, :moving_decisecs)}",
      "AT+Static=#{Keyword.fetch!(config, :static_decisecs)}",
      "AT+Exit=#{Keyword.fetch!(config, :exit_decisecs)}",
      "AT+START"
    ]
    |> Enum.map(&(&1 <> "\n"))
  end

  @doc """
  Classify a single response line (one logical line, without trailing newline).

    * `:ok` – `AT+OK`, advance to next command
    * `:retry` – `Save Para Fail`, resend the same command
    * `:other` – anything else (informational chatter, unknown banner)
  """
  @spec classify_response(String.t()) :: :ok | :retry | :other
  def classify_response(line) do
    cond do
      String.contains?(line, "AT+OK") -> :ok
      String.contains?(line, "Save Para Fail") -> :retry
      true -> :other
    end
  end
end
