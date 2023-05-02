defmodule Sim.Generator do
  use GenServer

  @max_value 8

  alias Sim.Protobuf.Packet
  alias Sim.Protobuf.Frame

  @invader [
    [
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      7,
      7,
      7,
      7,
      0,
      0,
      0,
      7,
      7,
      7,
      7,
      7,
      7,
      0,
      7,
      7,
      0,
      7,
      7,
      0,
      7,
      7,
      7,
      7,
      0,
      7,
      7,
      0,
      7,
      7,
      0,
      7,
      7,
      7,
      7,
      7,
      7,
      0,
      0,
      0,
      7,
      0,
      0,
      7,
      0,
      0,
      7,
      7,
      0,
      0,
      0,
      0,
      7,
      7
    ],
    [
      0,
      0,
      7,
      7,
      7,
      7,
      0,
      0,
      0,
      7,
      7,
      7,
      7,
      7,
      7,
      0,
      7,
      7,
      0,
      7,
      7,
      0,
      7,
      7,
      7,
      7,
      0,
      7,
      7,
      0,
      7,
      7,
      0,
      7,
      7,
      7,
      7,
      7,
      7,
      0,
      0,
      0,
      7,
      0,
      0,
      7,
      0,
      0,
      0,
      0,
      7,
      0,
      0,
      7,
      0,
      0,
      0,
      0,
      7,
      0,
      0,
      7,
      0,
      0
    ]
  ]

  def spawn_link(opts \\ []) do
    GenServer.start_link(__MODULE__, [], opts)
  end

  def init(_) do
    {:ok, socket} = :gen_udp.open(1234, [:binary, active: true, broadcast: true])
    :ok = :gen_udp.connect(socket, {127, 0, 0, 1}, Application.get_env(:sim, :udp_port))

    pixels = List.duplicate(0, 8 * 8 * 10)

    :timer.send_interval(100, self(), :tick)
    {:ok, %{pixels: pixels, socket: socket, tick: 0}}
  end

  def handle_info(:tick, %{socket: socket, pixels: pixels, tick: tick} = state) do
    pixels =
      pixels
      |> Enum.map(fn _ ->
        :rand.uniform(5)
      end)

    invader = @invader |> Enum.at(rem(tick, 2))
    pixels = invader ++ Enum.drop(pixels, length(invader))

    frame = %Frame{data: pixels |> :binary.list_to_bin(), maxval: @max_value}
    packet = %Packet{content: {:frame, frame}}

    :ok = :gen_udp.send(socket, Protobuf.encode(packet))

    {:noreply, %{state | pixels: pixels, tick: tick + 1}}
  end
end
