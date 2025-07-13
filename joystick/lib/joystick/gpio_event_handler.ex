defmodule Joystick.GpioEventHandler do
  use GenServer
  require Logger

  alias Joystick.{Protobuf, UDP}

  @gpio_pins [
    14,
    15,
    18,
    23,
    24,
    25,
    8,
    7,
    1,
    12,
    16,
    20
  ]

  @tick_interval_ms 1
  @debounce_timeout_ms 15

  defmodule State do
    defstruct gpio_refs: %{}, debounce_events: %{}
  end

  defmodule DebounceEvent do
    defstruct [:value, :timestamp]
  end

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(_) do
    gpio_refs =
      @gpio_pins
      |> Enum.with_index(1)
      |> Enum.map(fn {pin, button_num} ->
        Logger.info("Opening GPIO pin #{pin} for button #{button_num}")
        {:ok, gpio} = Circuits.GPIO.open(pin, :input, pull_mode: :pullup)

        :ok = Circuits.GPIO.set_interrupts(gpio, :both)

        {pin, {gpio, button_num}}
      end)
      |> Enum.into(%{})

    :timer.send_interval(@tick_interval_ms, :tick)
    {:ok, %State{gpio_refs: gpio_refs, debounce_events: %{}}}
  end

  def handle_info(
        {:circuits_gpio, pin, _timestamp, value},
        %State{gpio_refs: gpio_refs, debounce_events: debounce_events} = state
      ) do
    now = System.system_time(:millisecond)
    value = if value == 0, do: 1, else: 0

    # Logger.debug("GPIO pin #{pin} value: #{value}")

    case Map.get(gpio_refs, pin) do
      {_gpio, button_num} ->
        debounce_event = %DebounceEvent{
          value: value,
          timestamp: now
        }

        new_debounce_events = Map.put(debounce_events, button_num, debounce_event)
        {:noreply, %State{state | debounce_events: new_debounce_events}}

      nil ->
        Logger.warning("Unexpected GPIO interrupt from pin #{pin}")
        {:noreply, state}
    end
  end

  def handle_info(:tick, %State{debounce_events: debounce_events} = state) do
    now = System.system_time(:millisecond)

    remaining =
      Enum.reduce(debounce_events, %{}, fn {button_num, db_event}, acc ->
        if now - db_event.timestamp >= @debounce_timeout_ms do
          Logger.debug("Event button #{button_num} #{db_event.value}")

          %Protobuf.InputEvent{
            type: String.to_existing_atom("BUTTON_#{button_num}"),
            value: db_event.value
          }
          |> UDP.send()

          acc
        else
          Map.put(acc, button_num, db_event)
        end
      end)

    {:noreply, %State{state | debounce_events: remaining}}
  end

  def handle_info(msg, state) do
    Logger.warning("Unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  def terminate(_reason, %State{gpio_refs: gpio_refs}) do
    Enum.each(gpio_refs, fn {_pin, {gpio, _button_num}} ->
      Circuits.GPIO.close(gpio)
    end)

    :ok
  end
end
