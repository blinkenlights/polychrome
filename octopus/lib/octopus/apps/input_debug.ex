defmodule Octopus.Apps.InputDebug do
  use Octopus.App
  require Logger

  alias Octopus.ColorPalette
  alias Octopus.Protobuf.{Frame, InputEvent}

  @frame_rate 60
  @frame_time_ms trunc(1000 / @frame_rate)

  defmodule JoyState do
    defstruct [:buttons]

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

          type in [:BUTTON_1_A, :BUTTON_2_A] ->
            case value do
              1 -> {[:a], []}
              _ -> {[], [:a]}
            end

          type in [:BUTTON_1_B, :BUTTON_2_B] ->
            case value do
              1 -> {[:b], []}
              _ -> {[], [:b]}
            end
        end

      new_js = Enum.reduce(releases, js, fn b, acc -> acc |> release(b) end)
      Enum.reduce(presses, new_js, fn b, acc -> acc |> press(b) end)
    end
  end

  defmodule ButtonState do
    defstruct [:buttons, :joy1, :joy2]

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
        type when type in [:AXIS_X_1, :AXIS_Y_1, :BUTTON_1_A, :BUTTON_1_B] ->
          %ButtonState{bs | joy1: bs.joy1 |> JoyState.handle_event(type, value)}

        type when type in [:AXIS_X_2, :AXIS_Y_2, :BUTTON_2_A, :BUTTON_2_B] ->
          %ButtonState{bs | joy1: bs.joy2 |> JoyState.handle_event(type, value)}

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

  defmodule Screen do
    defstruct [:pixels]

    def new() do
      %Screen{
        pixels:
          [
            0
          ]
          #   1,
          #   2,
          #   3,
          #   0,
          #   1,
          #   2,
          #   3,
          #   4,
          #   5,
          #   6,
          #   7,
          #   4,
          #   5,
          #   6,
          #   7,
          #   8,
          #   9,
          #   10,
          #   11,
          #   8,
          #   9,
          #   10,
          #   11,
          #   12,
          #   13,
          #   14,
          #   15,
          #   12,
          #   13,
          #   14,
          #   15
          # ]
          |> Stream.cycle()
          |> Stream.take(8 * 8)
          |> Enum.to_list()
      }
    end

    defp index_to_coord(i) do
      {rem(i, 8), floor(i / 8)}
    end

    def set_pixels(%Screen{} = screen, tuples) do
      screen_map =
        screen.pixels
        |> Enum.with_index()
        |> Enum.reduce(%{}, fn {v, i}, acc ->
          acc
          |> Map.put(index_to_coord(i), v)
        end)

      screen_map =
        tuples
        |> Enum.reduce(screen_map, fn {coord, value}, acc ->
          acc |> Map.put(coord, value)
        end)

      new_pixels =
        0..63
        |> Enum.reduce([], fn i, acc ->
          [
            screen_map
            |> Map.get(index_to_coord(i))
            | acc
          ]
        end)
        |> Enum.reverse()

      %Screen{screen | pixels: new_pixels}
    end
  end

  defmodule State do
    defstruct [:position, :color, :palette, :screen, :button_state]
  end

  def name(), do: "Input Debugger"

  def init(_args) do
    state = %State{
      position: 0,
      color: 1,
      palette: ColorPalette.load("pico-8"),
      screen: Screen.new(),
      button_state: ButtonState.new()
    }

    :timer.send_interval(@frame_time_ms, :tick)
    {:ok, state}
  end

  def handle_info(:tick, %State{} = state) do
    render_frame(state)
    {:noreply, state}
  end

  def handle_input(
        %InputEvent{type: type, value: value} = event,
        %State{button_state: bs} = state
      ) do
    Logger.info("Input Debug: #{inspect(event)}")

    new_bs = bs |> ButtonState.handle_event(type, value) |> IO.inspect()

    {:noreply, %State{state | button_state: new_bs}}
  end

  defp screen_button_color(sb_index), do: sb_index + 4

  defp render_frame(%State{} = state) do
    # collect some painting
    pixel_tuples =
      [
        {:BUTTON_1, {0, 1}},
        {:BUTTON_2, {0, 0}},
        {:BUTTON_3, {1, 0}},
        {:BUTTON_4, {2, 0}},
        {:BUTTON_5, {3, 0}},
        {:BUTTON_6, {4, 0}},
        {:BUTTON_7, {5, 0}},
        {:BUTTON_8, {6, 0}},
        {:BUTTON_9, {7, 0}},
        {:BUTTON_10, {7, 1}}
      ]
      |> Enum.with_index()
      |> Enum.reduce([], fn {{b, coord}, index}, acc ->
        [
          {coord,
           if state.button_state |> ButtonState.button?(b) do
             screen_button_color(index)
           else
             1
           end}
          | acc
        ]
      end)

    screen =
      state.screen
      |> Screen.set_pixels(pixel_tuples)

    paint_screen = fn data, screen_index ->
      data
      |> Enum.with_index()
      |> Enum.map(fn {v, i} ->
        if floor(i / 64) == screen_index do
          screen_button_color(screen_index)
        else
          v
        end
      end)
      |> Enum.to_list()
    end

    data =
      screen.pixels
      #      |> IO.inspect()
      |> Stream.cycle()
      |> Stream.take(8 * 8 * 10)
      |> Enum.to_list()

    # make whole window light up for screen buttons
    data =
      0..9
      |> Enum.reduce(data, fn i, acc ->
        cond do
          state.button_state |> ButtonState.screen_button?(i) ->
            paint_screen.(acc, i)

          true ->
            acc
        end
      end)

    %Frame{
      data: data,
      palette: state.palette
    }
    |> send_frame()
  end
end
