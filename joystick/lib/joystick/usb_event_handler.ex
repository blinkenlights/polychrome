defmodule Joystick.UsbEventHandler do
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

  # Parse joystick buttons
  defp parse_event(device, {:ev_key, button, value} = event) when button in @supported_buttons do
    Logger.debug("Button event: #{inspect(event)} #{inspect(device)}}")

    case joystick_button_mapping(device, button) do
      {:screen_button, button_num} ->
        # Screen button mapping
        %Protobuf.InputEvent{
          type: String.to_existing_atom("BUTTON_#{button_num}"),
          value: value
        }

      {:joystick_button, joystick_num, joy_button} ->
        # Generate protobuf for network transmission
        %Protobuf.InputEvent{
          type: joystick_button_to_protobuf(joystick_num, joy_button),
          value: value
        }

      :menu_button ->
        %Protobuf.InputEvent{
          type: :BUTTON_MENU,
          value: value
        }

      nil ->
        nil
    end
  end

  # Parse joystick axis
  defp parse_event(device, {:ev_abs, axis, value} = event) when axis in @supported_axis do
    Logger.debug("Axis event: #{inspect(event)} #{inspect(device)}}")

    case joystick_axis_mapping(device, axis) do
      {joystick_num, axis_type} ->
        # Generate protobuf for network transmission
        %Protobuf.InputEvent{
          type: axis_to_protobuf(joystick_num, axis_type),
          value: direction_value(value, axis)
        }

      nil ->
        nil
    end
  end

  defp parse_event(device, event) do
    Logger.warning("Unexpected joystick event #{inspect(event)} on device #{inspect(device)}")
    nil
  end

  # Map physical buttons to logical functions
  defp joystick_button_mapping("/dev/input/event0", :btn_trigger), do: {:screen_button, 1}
  defp joystick_button_mapping("/dev/input/event0", :btn_thumb), do: {:screen_button, 2}
  defp joystick_button_mapping("/dev/input/event0", :btn_top2), do: {:screen_button, 3}
  defp joystick_button_mapping("/dev/input/event0", :btn_top), do: {:screen_button, 4}
  defp joystick_button_mapping("/dev/input/event0", :btn_base), do: {:screen_button, 5}

  defp joystick_button_mapping("/dev/input/event1", :btn_thumb), do: {:screen_button, 6}
  defp joystick_button_mapping("/dev/input/event1", :btn_trigger), do: {:screen_button, 7}
  defp joystick_button_mapping("/dev/input/event1", :btn_base5), do: {:screen_button, 8}
  defp joystick_button_mapping("/dev/input/event1", :btn_top), do: {:screen_button, 9}
  defp joystick_button_mapping("/dev/input/event1", :btn_top2), do: {:screen_button, 10}

  defp joystick_button_mapping("/dev/input/event0", :btn_base6), do: {:joystick_button, 1, :a}
  defp joystick_button_mapping("/dev/input/event0", :btn_pinkie), do: {:joystick_button, 1, :a}
  defp joystick_button_mapping("/dev/input/event1", :btn_base2), do: {:joystick_button, 2, :a}
  defp joystick_button_mapping("/dev/input/event1", :btn_base6), do: {:joystick_button, 2, :a}

  defp joystick_button_mapping("/dev/input/event1", :btn_base), do: :menu_button
  defp joystick_button_mapping(_, _), do: nil

  # Map physical axes to logical joysticks
  defp joystick_axis_mapping("/dev/input/event0", :abs_x), do: {1, :x}
  defp joystick_axis_mapping("/dev/input/event0", :abs_y), do: {1, :y}
  defp joystick_axis_mapping("/dev/input/event1", :abs_x), do: {2, :x}
  defp joystick_axis_mapping("/dev/input/event1", :abs_y), do: {2, :y}
  defp joystick_axis_mapping(_, _), do: nil

  # Convert joystick buttons to protobuf format for network transmission
  defp joystick_button_to_protobuf(1, :a), do: :BUTTON_A_1
  defp joystick_button_to_protobuf(2, :a), do: :BUTTON_A_2
  defp joystick_button_to_protobuf(1, :b), do: :BUTTON_B_1
  defp joystick_button_to_protobuf(2, :b), do: :BUTTON_B_2

  defp axis_to_protobuf(1, :x), do: :AXIS_X_1
  defp axis_to_protobuf(1, :y), do: :AXIS_Y_1
  defp axis_to_protobuf(2, :x), do: :AXIS_X_2
  defp axis_to_protobuf(2, :y), do: :AXIS_Y_2

  defp direction_value(0, :abs_x), do: -1
  defp direction_value(127, :abs_x), do: 0
  defp direction_value(255, :abs_x), do: 1

  defp direction_value(0, :abs_y), do: -1
  defp direction_value(127, :abs_y), do: 0
  defp direction_value(255, :abs_y), do: 1
end
