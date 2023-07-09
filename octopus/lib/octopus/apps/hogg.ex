defmodule Octopus.Apps.Hogg do
  use Octopus.App
  require Logger

  alias Octopus.Canvas
  alias Octopus.ColorPalette
  alias Octopus.Protobuf.{Frame, InputEvent}

  @frame_rate 60
  @frame_time_ms trunc(1000 / @frame_rate)

  defmodule Player do
    defstruct pos: {39, 1}, vel: {0, 0}, base_color: [128, 255, 128], is_ducking: false

    def new(0) do
      %Player{pos: {8 * 3 + 4, 1}}
    end

    def new(1) do
      %Player{pos: {8 * 6 + 3, 1}, base_color: [255, 128, 128]}
    end
  end

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

  defmodule State do
    defstruct [:palette, :canvas, :button_state, :players, :t]
  end

  def name(), do: "Hogg"

  def init(_args) do
    state = %State{
      palette: ColorPalette.load("pico-8"),
      canvas: Canvas.new(80, 8),
      button_state: ButtonState.new(),
      players: [Player.new(0), Player.new(1)],
      t: 0
    }

    :timer.send_interval(@frame_time_ms, :tick)
    {:ok, state}
  end

  def clamp(v, min, _max) when v < min, do: min
  def clamp(v, _min, max) when v > max, do: max
  def clamp(v, _, _), do: v

  def clamp(v, max) when v > max, do: max
  def clamp(v, max) when v < -max, do: -max
  def clamp(v, _), do: v

  def handle_info(:tick, %State{players: [p1, p2], button_state: bs} = state) do
    gravity = 0.006
    horz_acc = 0.01
    horz_max = 0.20
    jump = -0.2

    players =
      [{p1, bs.joy1}, {p2, bs.joy2}]
      |> Enum.map(fn {%Player{pos: {x, y}, vel: {dx, dy}} = p, %JoyState{} = joy} ->
        %Player{
          p
          | vel: {
              cond do
                JoyState.button?(joy, :l) -> dx - horz_acc
                JoyState.button?(joy, :r) -> dx + horz_acc
                true -> dx * 0.5
              end
              |> clamp(horz_max),
              cond do
                dy >= 0 and (JoyState.button?(joy, :a) or JoyState.button?(joy, :u)) ->
                  jump

                true ->
                  if y < 7 do
                    dy + gravity
                  else
                    0
                  end
              end
            },
            is_ducking: joy |> JoyState.button?(:d)
        }
      end)
      # apply vel
      |> Enum.map(fn %Player{pos: {x, y}, vel: {dx, dy}} = p ->
        %Player{p | pos: {(x + dx) |> clamp(0, 79), (y + dy) |> clamp(0, 7)}}
      end)

    state = %State{state | players: players}
    {:noreply, tick(state)}
  end

  def handle_input(
        %InputEvent{type: type, value: value} = _event,
        %State{button_state: bs} = state
      ) do
    # Logger.info("Input Debug: #{inspect(event)}")

    new_bs = bs |> ButtonState.handle_event(type, value) |> IO.inspect()

    {:noreply, %State{state | button_state: new_bs}}
  end

  defp tick(%State{t: t} = state) do
    render_frame(state)
    %State{state | t: t + 1}
  end

  defp render_frame(%State{button_state: _bs, t: t} = state) do
    canvas =
      state.canvas
      |> Canvas.put_pixel({rem(Integer.floor_div(t, 10), state.canvas.width), 0}, [123, 255, 255])

    #    state.players |> IO.inspect()

    state.players
    |> Enum.reduce(canvas, fn %Player{pos: {x, y}} = player, canvas ->
      x = floor(x)
      y = floor(y)

      canvas
      |> Canvas.put_pixel({x, y}, player.base_color)
      |> (fn
            c, true -> c
            c, false -> c |> Canvas.put_pixel({x, y - 1}, player.base_color)
          end).(player.is_ducking)
    end)
    |> Canvas.to_frame()
    |> send_frame()
  end
end
