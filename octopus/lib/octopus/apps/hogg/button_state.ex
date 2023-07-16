defmodule Octopus.Apps.Hogg.ButtonState do
  defstruct [:buttons, :joy1, :joy2]

  alias Octopus.Apps.Hogg
  alias Hogg.ButtonState
  alias Hogg.JoyState

  @button_map 1..10
              |> Enum.map(fn i -> {"BUTTON_#{i}" |> String.to_atom(), i - 1} end)
              |> Enum.into(%{})

  def new() do
    %ButtonState{
      buttons: MapSet.new(),
      joy1: JoyState.new(),
      joy2: JoyState.new()
    }
  end

  def press(%ButtonState{buttons: buttons} = bs, button) do
    %ButtonState{bs | buttons: buttons |> MapSet.put(button)}
  end

  def release(%ButtonState{buttons: buttons} = bs, button) do
    %ButtonState{bs | buttons: buttons |> MapSet.delete(button)}
  end

  def handle_event(%ButtonState{} = bs, type, value) do
    case type do
      type when type in [:AXIS_X_1, :AXIS_Y_1, :BUTTON_A_1, :BUTTON_B_1] ->
        %ButtonState{bs | joy1: bs.joy1 |> JoyState.handle_event(type, value)}

      type when type in [:AXIS_X_2, :AXIS_Y_2, :BUTTON_A_2, :BUTTON_B_2] ->
        %ButtonState{bs | joy2: bs.joy2 |> JoyState.handle_event(type, value)}

      button ->
        case value do
          1 -> bs |> press({:sb, button_to_index(button)}) |> press(button)
          0 -> bs |> release({:sb, button_to_index(button)}) |> release(button)
        end
    end
  end

  def button_to_index(button) do
    Map.get(@button_map, button)
  end

  def index_to_button(index) do
    "BUTTON_#{index + 1}" |> String.to_existing_atom()
  end

  def screen_button?(%ButtonState{buttons: buttons}, index),
    do: MapSet.member?(buttons, index_to_button(index))

  def button?(%ButtonState{buttons: buttons}, button),
    do: MapSet.member?(buttons, button)
end
