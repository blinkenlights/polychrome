defmodule Octopus.Apps.Train do
  use Octopus.App, category: :animation

  alias Octopus.{Canvas, Image}
  alias Octopus.Protobuf.InputEvent

  @fps 60

  defmodule State do
    defstruct [:canvas, :time, :x, :acceleration, :speed]
  end

  def name(), do: "Train Simulator"

  def init(_args) do
    canvas = Image.load("landscape")

    :timer.send_interval(trunc(1000 / @fps), :tick)
    :timer.send_interval(10_000, :change_acceleration)

    {:ok, %State{canvas: canvas, time: 0, x: 0, acceleration: 0.1, speed: 0}}
  end

  def add_window_corners(canvas) do
    window_locations = for x <- 0..(9 * (8 + 18))//8 + 18, do: {x, 0}

    Enum.reduce(window_locations, canvas, fn {x, y}, canvas ->
      canvas
      |> Canvas.put_pixel({x, y}, {0, 0, 0})
      |> Canvas.put_pixel({x + 7, y}, {0, 0, 0})
      |> Canvas.put_pixel({x, y + 7}, {0, 0, 0})
      |> Canvas.put_pixel({x + 7, y + 7}, {0, 0, 0})
    end)
  end

  def handle_info(:tick, %State{} = state) do
    canvas2 = state.canvas |> Canvas.translate({trunc(state.x), 0}, true)

    canvas2
    |> add_window_corners()
    |> Canvas.to_frame(drop: true)
    |> send_frame()

    speed = state.speed + state.acceleration / @fps
    # Limit speed
    speed = min(10, max(-10, speed))
    # Apply friction
    speed = speed * (1 / (1 + 0.1 / @fps))

    {:noreply, %State{state | time: state.time + 1 / @fps, speed: speed, x: state.x + speed}}
  end

  def handle_info(:change_acceleration, %State{acceleration: 0, speed: speed} = state)
      when speed > 0 do
    {:noreply, %State{state | acceleration: -0.1}}
  end

  def handle_info(:change_acceleration, %State{acceleration: 0, speed: speed} = state)
      when speed <= 0 do
    {:noreply, %State{state | acceleration: 0.1}}
  end

  def handle_info(:change_acceleration, %State{acceleration: 0.1} = state) do
    {:noreply, %State{state | acceleration: 0}}
  end

  def handle_info(:change_acceleration, %State{acceleration: -0.1} = state) do
    {:noreply, %State{state | acceleration: 0}}
  end

  def handle_input(%InputEvent{type: :AXIS_X_1, value: value}, state) do
    state = %State{state | acceleration: -0.1 * value}
    {:noreply, state}
  end

  def handle_input(%InputEvent{type: _, value: _}, state) do
    {:noreply, state}
  end
end
