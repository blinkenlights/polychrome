defmodule Octopus.Apps.MarioRun do
  alias Octopus.Protobuf.InputEvent
  alias Octopus.Canvas
  alias Octopus.Sprite

  use Octopus.App

  @loops %{
    run: [
      {0, {80, 130}, false},
      {1, {80, 130}, false},
      {2, {80, 130}, false},
      {3, {80, 130}, false},
      {4, {80, 130}, false},
      {5, {80, 130}, false}
    ],
    look1: [
      {6, 500, false},
      {7, 100, false},
      {8, 500, false}
    ],
    look2: [
      {6, 500, false},
      {7, 100, false},
      {8, 100, false},
      {7, 100, false},
      {6, 500, false}
    ],
    look3: [
      {6, 500, false},
      {7, 100, false},
      {8, 500, false},
      {6, 500, true},
      {7, 100, true},
      {8, 500, true}
    ]
  }

  defmodule State do
    defstruct [
      :canvas,
      :time,
      :sprite_sheets,
      :loop,
      :next_loop,
      :character,
      :current_frame,
      :speed
    ]
  end

  def name, do: "Mario Run"

  def icon, do: Canvas.from_webp("mario")

  def config_schema do
    %{
      speed: {"Speed", :float, %{default: 1.0, min: 0.1, max: 10.0}}
    }
  end

  def get_config(%State{} = state) do
    %{speed: state.speed}
  end

  def init(_) do
    sprite_sheets = %{
      mario: "mario-run",
      luigi: "luigi-run"
    }

    state = %State{
      canvas: Canvas.new(8, 8),
      time: 0.0,
      sprite_sheets: sprite_sheets,
      character: :mario,
      current_frame: 0,
      loop: :run,
      next_loop: :run,
      speed: 1.0
    }

    Process.send_after(self(), :tick, 0)

    {:ok, state}
  end

  defp animate(%State{current_frame: current_frame, next_loop: next_loop, loop: loop} = state) do
    if state.current_frame + 1 >= length(@loops[state.loop]) do
      %State{state | loop: next_loop, current_frame: 0}
    else
      %State{state | loop: loop, current_frame: current_frame + 1}
    end
  end

  defp schedule_next_frame({min, max}, speed) do
    duration = Enum.random(min..max)
    schedule_next_frame(duration, speed)
  end

  defp schedule_next_frame(duration, speed) do
    Process.send_after(self(), :tick, trunc(duration * (1 / speed)))
  end

  def handle_info(:tick, %State{} = state) do
    {sprite_index, duration, flip} = Enum.at(@loops[state.loop], state.current_frame)
    sprite_sheet = state.sprite_sheets[state.character]
    sprite = Sprite.load(sprite_sheet, sprite_index)

    canvas =
      state.canvas
      |> Canvas.clear()
      |> Canvas.overlay(sprite)
      |> then(&if(flip, do: Canvas.flip_horizontal(&1), else: &1))

    canvas |> Canvas.to_frame() |> send_frame()

    state = animate(state)

    schedule_next_frame(duration, state.speed)

    {:noreply, %State{state | canvas: canvas}}
  end

  def handle_config(%{speed: speed}, state) do
    {:noreply, %State{state | speed: speed}}
  end

  def handle_input(%InputEvent{type: :BUTTON_1, value: 1}, state) do
    {:noreply, %State{state | next_loop: :run}}
  end

  def handle_input(%InputEvent{type: :BUTTON_2, value: 1}, state) do
    {:noreply, %State{state | next_loop: :look1}}
  end

  def handle_input(%InputEvent{type: :BUTTON_3, value: 1}, state) do
    {:noreply, %State{state | next_loop: :look2}}
  end

  def handle_input(%InputEvent{type: :BUTTON_4, value: 1}, state) do
    {:noreply, %State{state | next_loop: :look3}}
  end

  def handle_input(%InputEvent{type: :BUTTON_10, value: 1}, %State{character: :mario} = state) do
    {:noreply, %State{state | character: :luigi}}
  end

  def handle_input(%InputEvent{type: :BUTTON_10, value: 1}, %State{character: :luigi} = state) do
    {:noreply, %State{state | character: :mario}}
  end

  def handle_input(_event, state) do
    {:noreply, state}
  end
end
