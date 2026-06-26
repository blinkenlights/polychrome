defmodule Octopus.Radar.Transport do
  @moduledoc """
  Byte-transport abstraction for `Octopus.Radar.Sensor`.

  The sensor's phase machine, AT handshake and binary protocol parsing are
  transport-agnostic: they only need something that can open a connection,
  accept written bytes, and deliver received bytes back as
  `{:circuits_uart, port, data}` messages to the owning process.

  Two implementations exist:

    * `Octopus.Radar.Transport.UART` — the real serial port (a thin delegate
      to `Circuits.UART`). This is the default and the behaviour is identical
      to talking to the hardware directly.
    * `Octopus.Radar.Transport.Mock` — an in-process fake device
      (`Octopus.Radar.Mock.Server`) that speaks the same AT + binary wire
      protocol, used by the mock mode.

  Both deliver received bytes to the owner using the **same** message shape
  (`{:circuits_uart, port, data}` / `{:circuits_uart, port, {:error, reason}}`)
  so the `Sensor` `handle_info/2` clauses are unchanged regardless of
  transport.
  """

  @typedoc "Opaque transport handle (e.g. a `Circuits.UART` pid or a mock server ref)."
  @type handle :: term()

  @doc "Start the transport, returning an opaque handle used by the other callbacks."
  @callback start_link(opts :: keyword()) :: {:ok, handle()} | {:error, term()}

  @doc """
  Open the connection. `opts` carries the serial-port settings (speed, framing,
  …) for the UART transport; the mock transport ignores them.
  """
  @callback open(handle(), port_name :: String.t(), opts :: keyword()) ::
              :ok | {:error, term()}

  @doc "Write bytes to the device."
  @callback write(handle(), iodata()) :: :ok | {:error, term()}

  @doc "Close the connection."
  @callback close(handle()) :: :ok | {:error, term()}
end
