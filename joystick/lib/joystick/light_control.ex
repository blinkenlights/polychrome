defmodule Joystick.LightControl do
  use GenServer
  require Logger
  alias Joystick.Protobuf.{InputLightEvent}

  @led_mapping [11, 2, 3, 4, 5, 6, 17, 27, 9, 10]
  @tick_interval_ms trunc(1000 / 60)

  defmodule State do
    defstruct [:leds, durations: %{}]
  end

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def handle_light_event(%InputLightEvent{type: type, duration: duration}) do
    GenServer.cast(__MODULE__, {:input_light_event, type, duration})
  end

  def init(:ok) do
    Logger.info("Starting #{__MODULE__}")

    leds =
      @led_mapping
      |> Enum.map(&Circuits.GPIO.open("GPIO#{&1}", :output))
      |> Enum.map(&elem(&1, 1))
      |> Enum.with_index(1)
      |> Enum.map(fn {pin, i} -> {"BUTTON_#{i}" |> String.to_existing_atom(), pin} end)
      |> Enum.into(%{})

    :timer.send_interval(@tick_interval_ms, :tick)

    {:ok, %State{leds: leds}}
  end

  def handle_cast({:input_light_event, type, duration}, %State{} = state) do
    now = System.system_time(:millisecond)
    expiration = now + duration

    durations = Map.put(state.durations, type, expiration)

    led = Map.get(state.leds, type)
    Circuits.GPIO.write(led, 1)

    {:noreply, %State{state | durations: durations}}
  end

  def handle_info(:tick, %State{} = state) do
    now = System.system_time(:millisecond)

    {expired, durations} =
      state.durations
      |> Enum.split_with(fn {_, expiration} -> expiration < now end)

    Enum.each(expired, fn {type, _} ->
      led = Map.get(state.leds, type)
      Circuits.GPIO.write(led, 0)
    end)

    {:noreply, %State{state | durations: Enum.into(durations, %{})}}
  end
end
