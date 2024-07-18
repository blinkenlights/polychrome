defmodule Joystick.EventHandler do
  use GenServer
  require Logger

  alias Joystick.{Protobuf, UDP}

  @joystick_name "DragonRise Inc.   Generic   USB  Joystick  "
  @supported_buttons [
    :btn_top,
    :btn_top2,
    :btn_thumb,
    :btn_thumb2,
    :btn_trigger,
    :btn_base5,
    :btn_pinkie,
    :btn_base2,
    :btn_base6,
    :btn_base
  ]
  @supported_axis [:abs_x, :abs_y]

  defmodule State do
    defstruct []
  end

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(_) do
    InputEvent.enumerate()
    |> Enum.filter(fn {_, %InputEvent.Info{} = info} -> info.name == @joystick_name end)
    |> Enum.map(fn {device, _info} ->
      Logger.info("Subscribing to joystick on device #{inspect(device)}")
      {:ok, _pid} = InputEvent.start_link(device)
    end)

    {:ok, %State{}}
  end

  def handle_info({:input_event, device, events}, state) do
    events
    |> Enum.map(&parse_event(device, &1))
    |> Enum.reject(&is_nil/1)
    |> Enum.map(fn event ->
      Logger.debug("Input event: #{inspect(event)}")
      event
    end)
    |> Enum.map(&UDP.send/1)

    {:noreply, state}
  end

  defp parse_event(_, {:ev_abs, :abs_z, _}), do: nil
  defp parse_event(_, {:ev_msc, _, _}), do: nil

  defp parse_event(device, {:ev_key, button, value} = event) when button in @supported_buttons do
    Logger.debug("Button event: #{inspect(event)} #{inspect(device)}}")

    %Protobuf.InputEvent{
      type: type_from_button(device, button),
      value: value
    }
  end

  defp parse_event(device, {:ev_abs, axis, value} = event) when axis in @supported_axis do
    Logger.debug("Button event: #{inspect(event)} #{inspect(device)}}")

    %Protobuf.InputEvent{
      type: type_from_direction(device, axis),
      value: direction_value(value, axis)
    }
  end

  defp parse_event(device, event) do
    Logger.warning("Unexpected joystick event #{inspect(event)} on device #{inspect(device)}")
    nil
  end

  defp type_from_button("/dev/input/event0", :btn_trigger), do: :BUTTON_1
  defp type_from_button("/dev/input/event0", :btn_thumb), do: :BUTTON_2
  defp type_from_button("/dev/input/event0", :btn_top2), do: :BUTTON_3
  defp type_from_button("/dev/input/event0", :btn_top), do: :BUTTON_4
  defp type_from_button("/dev/input/event0", :btn_base), do: :BUTTON_5

  defp type_from_button("/dev/input/event1", :btn_thumb), do: :BUTTON_6
  defp type_from_button("/dev/input/event1", :btn_trigger), do: :BUTTON_7
  defp type_from_button("/dev/input/event1", :btn_base5), do: :BUTTON_8
  defp type_from_button("/dev/input/event1", :btn_top), do: :BUTTON_9
  defp type_from_button("/dev/input/event1", :btn_top2), do: :BUTTON_10

  defp type_from_button("/dev/input/event0", :btn_base6), do: :BUTTON_A_1
  defp type_from_button("/dev/input/event0", :btn_pinkie), do: :BUTTON_A_1
  defp type_from_button("/dev/input/event1", :btn_base2), do: :BUTTON_A_2
  defp type_from_button("/dev/input/event1", :btn_base6), do: :BUTTON_A_2

  defp type_from_button("/dev/input/event1", :btn_base), do: :BUTTON_MENU

  defp type_from_direction("/dev/input/event0", :abs_x), do: :AXIS_X_1
  defp type_from_direction("/dev/input/event0", :abs_y), do: :AXIS_Y_1
  defp type_from_direction("/dev/input/event1", :abs_x), do: :AXIS_X_2
  defp type_from_direction("/dev/input/event1", :abs_y), do: :AXIS_Y_2

  defp direction_value(0, :abs_x), do: -1
  defp direction_value(127, :abs_x), do: 0
  defp direction_value(255, :abs_x), do: 1

  defp direction_value(0, :abs_y), do: -1
  defp direction_value(127, :abs_y), do: 0
  defp direction_value(255, :abs_y), do: 1
end
