defmodule Octopus.Radar.Transport.Mock do
  @moduledoc """
  Mock transport — connects a `Octopus.Radar.Sensor` to a per-sensor fake
  device (`Octopus.Radar.Mock.Server`) instead of a real serial port.

  The mock server is started and supervised separately (by `Octopus.Radar`);
  its reference is passed in via `transport_opts: [server: ref]`. This module
  is a stateless shim: `start_link/1` just returns that reference as the
  transport handle, and `open/3` / `write/2` / `close/1` forward to the
  server. The server delivers binary frames back to the owning `Sensor` as
  `{:circuits_uart, port, data}` messages, exactly like `Circuits.UART`.
  """

  @behaviour Octopus.Radar.Transport

  alias Octopus.Radar.Mock.Server

  @impl true
  def start_link(opts) do
    {:ok, Keyword.fetch!(opts, :server)}
  end

  @impl true
  def open(server, port, _opts) do
    Server.attach(server, self(), port)
  end

  @impl true
  def write(server, data) do
    Server.write(server, data)
  end

  @impl true
  def close(server) do
    Server.detach(server)
  end
end
