defmodule Joystick.EventHandler do
  use GenServer
  require Logger

  alias Joystick.{Protobuf, UDP}

  @joystick_name "DragonRise Inc.   Generic   USB  Joystick  "
  @supported_buttons [:btn_top, :btn_top2, :btn_thumb, :btn_thumb2, :btn_trigger]
  @supported_axis [:abs_x, :abs_y]

  defmodule State do
    defstruct []
  end

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, [{:name, __MODULE__}])
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

    # |> Enum.map(&Logger.info("Input event: #{inspect(&1)}"))
    |> Enum.map(&UDP.send/1)

    {:noreply, state}
  end

  defp parse_event(_, {:ev_abs, :abs_z, _}), do: nil
  defp parse_event(_, {:ev_msc, _, _}), do: nil

  defp parse_event(device, {:ev_key, button, value}) when button in @supported_buttons do
    %Protobuf.InputEvent{
      type: type_from_button(device, button),
      value: value
    }
  end

  defp parse_event(device, {:ev_abs, axis, value}) when axis in @supported_axis do
    %Protobuf.InputEvent{
      type: type_from_direction(device, axis),
      value: direction_value(value)
    }
  end

  defp parse_event(device, event) do
    Logger.warn("Unexpected joystick event #{inspect(event)} on device #{inspect(device)}")
    nil
  end

  defp type_from_button("/dev/input/event0", :btn_top2), do: :BUTTON_1
  defp type_from_button("/dev/input/event0", :btn_top), do: :BUTTON_2
  defp type_from_button("/dev/input/event0", :btn_thumb2), do: :BUTTON_3
  defp type_from_button("/dev/input/event0", :btn_thumb), do: :BUTTON_4
  defp type_from_button("/dev/input/event0", :btn_trigger), do: :BUTTON_5
  defp type_from_button("/dev/input/event1", :btn_top2), do: :BUTTON_6
  defp type_from_button("/dev/input/event1", :btn_top), do: :BUTTON_7
  defp type_from_button("/dev/input/event1", :btn_thumb2), do: :BUTTON_8
  defp type_from_button("/dev/input/event1", :btn_thumb), do: :BUTTON_9
  defp type_from_button("/dev/input/event1", :btn_trigger), do: :BUTTON_10

  defp type_from_direction("/dev/input/event0", :abs_x), do: :X_AXIS_1
  defp type_from_direction("/dev/input/event0", :abs_y), do: :Y_AXIS_1
  defp type_from_direction("/dev/input/event1", :abs_x), do: :X_AXIS_2
  defp type_from_direction("/dev/input/event1", :abs_y), do: :Y_AXIS_2

  defp direction_value(0), do: -1
  defp direction_value(127), do: 0
  defp direction_value(255), do: 1
end
