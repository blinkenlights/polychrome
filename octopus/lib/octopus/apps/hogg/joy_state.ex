defmodule Octopus.Apps.Hogg.JoyState do
  defstruct [:buttons]

  alias Octopus.Apps.Hogg
  alias Hogg.JoyState

  def new() do
    %JoyState{
      buttons: MapSet.new()
    }
  end

  def press(%JoyState{} = js, button) do
    %JoyState{
      buttons: js.buttons |> MapSet.put(button)
    }
  end

  def release(%JoyState{} = js, button) do
    %JoyState{
      buttons: js.buttons |> MapSet.delete(button)
    }
  end

  def handle_event(%JoyState{} = js, type, value) do
    {presses, releases} =
      cond do
        type in [:AXIS_X_1, :AXIS_X_2] ->
          case value do
            1 -> {[:r], [:l]}
            0 -> {[], [:r, :l]}
            -1 -> {[:l], [:r]}
          end

        type in [:AXIS_Y_1, :AXIS_Y_2] ->
          case value do
            1 -> {[:d], [:u]}
            0 -> {[], [:d, :u]}
            -1 -> {[:u], [:d]}
          end

        type in [:BUTTON_A_1, :BUTTON_A_2] ->
          case value do
            1 -> {[:a], []}
            _ -> {[], [:a]}
          end

        type in [:BUTTON_B_1, :BUTTON_B_2] ->
          case value do
            1 -> {[:b], []}
            _ -> {[], [:b]}
          end
      end

    new_js = Enum.reduce(releases, js, fn b, acc -> acc |> release(b) end)
    Enum.reduce(presses, new_js, fn b, acc -> acc |> press(b) end)
  end

  def button?(%JoyState{buttons: buttons}, button), do: buttons |> MapSet.member?(button)
end
