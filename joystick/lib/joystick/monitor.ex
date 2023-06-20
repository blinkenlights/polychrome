defmodule Joystick.Monitor do
  use GenServer
  require Logger

  @network_message_name_eth ["interface", "eth0", "connection"]
  @tick_interval 5000

  def start_link(_) do
    GenServer.start_link(__MODULE__, [])
  end

  def init(_) do
    Logger.info("Starting #{__MODULE__}")
    VintageNet.subscribe(@network_message_name_eth)

    initial_state = %{
      error_since: nil
    }

    state =
      VintageNet.get(@network_message_name_eth)
      |> handle_network_state(initial_state)

    :timer.send_interval(@tick_interval, :tick)

    {:ok, state}
  end

  def handle_info({VintageNet, @network_message_name_eth, old_value, new_value, _metadata}, state) do
    Logger.info(
      "#{__MODULE__}: new connection state: #{inspect(new_value)} (old: #{inspect(old_value)})"
    )

    {:noreply, handle_network_state(new_value, state)}
  end

  def handle_info(:tick, state) do
    System.cmd("vcgencmd", ["get_throttled"])
    |> handle_vcgencmd_response()

    {:noreply, state}
  end

  defp handle_network_state(:internet, state) do
    Nerves.Leds.set(:red, true)
    %{state | error_since: nil}
  end

  defp handle_network_state(:lan, state) do
    Nerves.Leds.set(:red, :slowblink)

    state
    |> maybe_set_error()
    |> maybe_restart
  end

  defp handle_network_state(_network_state, state) do
    Nerves.Leds.set(:red, :fastblink)

    state
    |> maybe_set_error()
    |> maybe_restart()
  end

  defp handle_vcgencmd_response({"throttled=0x" <> hex, 0}) do
    # see https://www.raspberrypi.org/documentation/raspbian/applications/vcgencmd.md
    <<_::4, past::4, _::12, current::4>> =
      hex |> String.trim() |> String.pad_leading(6, "0") |> Base.decode16!()

    case {past, current} do
      {0, 0} ->
        # all good
        Nerves.Leds.set(:green, true)

      {_, 0} ->
        # past bad, current good
        Application.put_env(:tr33_pi, :health_log, true)
        Nerves.Leds.set(:green, :slowblink)

      {_, _} ->
        # past and current bad
        if Application.get_env(:tr33_pi, :health_log, true) do
          Logger.warn(
            "#{__MODULE__}: System unhealthy, vcgencmd current: #{inspect(current)}, past: #{inspect(past)}"
          )

          Application.put_env(:tr33_pi, :health_log, false)
        end

        Nerves.Leds.set(:green, :fastblink)
    end
  end

  defp handle_vcgencmd_response(error) do
    Logger.error("#{__MODULE__}: Unexpected vcgencmd resonse: #{inspect(error)}")
    Nerves.Leds.set(:green, :fastblink)
  end

  defp maybe_set_error(%{error_since: nil} = state),
    do: %{state | error_since: System.os_time(:millisecond)}

  defp maybe_set_error(state), do: state

  @restart_timeout_ms 5 * 60 * 1000
  defp maybe_restart(%{error_since: nil} = state), do: state

  defp maybe_restart(%{error_since: millis} = state) do
    if System.os_time(:millisecond) - millis > @restart_timeout_ms do
      Nerves.Runtime.reboot()
    end

    state
  end
end
