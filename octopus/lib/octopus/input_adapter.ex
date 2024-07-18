defmodule Octopus.InputAdapter do
  use GenServer
  require Logger

  alias Octopus.Protobuf.SoundToLightControlEvent
  alias Octopus.{Protobuf, Mixer}
  alias Octopus.Protobuf.{InputEvent, InputLightEvent}

  @local_port 4423

  defmodule State do
    defstruct [:udp, :from_ip, :from_port]
  end

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def send_light_event(button, duration) when button in 1..10 do
    binary =
      %InputLightEvent{
        type: "BUTTON_#{button}" |> String.to_existing_atom(),
        duration: duration
      }
      |> Protobuf.encode()

    GenServer.cast(__MODULE__, {:send_binary, binary})
  end

  def init(:ok) do
    Logger.info("Starting input adapter. Listening on port #{@local_port}")
    {:ok, udp} = :gen_udp.open(@local_port, [:binary, active: true])

    {:ok, %State{udp: udp}}
  end

  def handle_cast({:send_binary, binary}, %State{udp: udp} = state) do
    :gen_udp.send(udp, {state.from_ip, state.from_port}, binary)
    {:noreply, state}
  end

  def handle_info({:udp, _socket, from_ip, from_port, packet}, state = %State{}) do
    case Protobuf.decode_packet(packet) do
      {:ok, %InputEvent{} = input_event} ->
        # Logger.debug("#{__MODULE__}: Received input event: #{inspect(input_event)}")
        Mixer.handle_input(input_event)

      {:ok, %SoundToLightControlEvent{} = stl_event} ->
        # Logger.debug("#{__MODULE__}: Received stl event event: #{inspect(stl_event)}")
        Mixer.handle_input(stl_event)

      {:ok, content} ->
        Logger.warning("#{__MODULE__}: Received unexpected packet: #{inspect(content)}")

      {:error, error} ->
        Logger.warning("#{__MODULE__}: Error decoding packet #{inspect(error)}")
    end

    {:noreply, %State{state | from_ip: from_ip, from_port: from_port}}
  end
end
