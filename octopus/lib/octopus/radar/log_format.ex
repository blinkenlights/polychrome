defmodule Octopus.Radar.LogFormat do
  @moduledoc false

  @doc "Map 1-based device_id to UI letter (1 → A, 2 → B, …)."
  @spec device_letter(pos_integer()) :: String.t()
  def device_letter(device_id) when is_integer(device_id) and device_id >= 1 do
    <<(?A + device_id - 1)::utf8>>
  end

  @doc """
  Compact port label for logs.

  `/dev/serial/by-id/usb-WCH.CN_USB_Quad_Serial_BDFFDFABCD-if02` → `BDFFDFABCD-if02`
  """
  @spec short_port(String.t()) :: String.t()
  def short_port("/dev/serial/by-id/usb-WCH.CN_USB_Quad_Serial_" <> rest), do: rest
  def short_port(path) when is_binary(path), do: Path.basename(path)

  @doc "Standard log prefix: `[radar B BDFFDFABCD-if02]`"
  @spec tag(pos_integer(), String.t()) :: String.t()
  def tag(device_id, port) do
    "[radar #{device_letter(device_id)} #{short_port(port)}]"
  end
end
