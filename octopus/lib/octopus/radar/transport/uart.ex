defmodule Octopus.Radar.Transport.UART do
  @moduledoc """
  Real serial-port transport — a thin delegate to `Circuits.UART`.

  This is the default transport for `Octopus.Radar.Sensor` and preserves the
  exact behaviour the sensor had when it called `Circuits.UART` directly:
  `Circuits.UART` delivers received bytes to the owner as
  `{:circuits_uart, port, data}` messages, which is precisely the contract
  `Octopus.Radar.Transport` defines.
  """

  @behaviour Octopus.Radar.Transport

  alias Circuits.UART

  @impl true
  def start_link(_opts) do
    UART.start_link()
  end

  @impl true
  def open(uart, port, opts) do
    UART.open(uart, port, opts)
  catch
    :exit, reason -> {:error, {:uart_exit, reason}}
  end

  @impl true
  def write(uart, data) do
    UART.write(uart, data)
  catch
    :exit, _ -> {:error, :uart_dead}
  end

  @impl true
  def close(uart) do
    UART.close(uart)
  catch
    :exit, _ -> :ok
  end
end
