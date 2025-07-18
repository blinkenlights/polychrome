defmodule Octopus.Apps.Train do
  use Octopus.App, category: :animation

  alias Octopus.{Canvas, Image}
  alias Octopus.Installation
  alias Octopus.Events.Event.Input, as: InputEvent

  @fps 60

  defmodule State do
    defstruct [:canvas, :time, :x, :acceleration, :speed]
  end

  def name(), do: "Train Simulator"

  def compatible?() do
    # Check if landscape image is compatible with current installation
    installation = Octopus.App.get_installation_info()

    gapped_width =
      installation.panel_count * installation.panel_width +
        (installation.panel_count - 1) * installation.panel_gap

    # Landscape image is 263px wide - check if it fits in gapped layout
    gapped_width >= 263
  end

  def app_init(_args) do
    # Configure for gapped panels layout (replaces Canvas.to_frame(drop: true))
    Octopus.App.configure_display(layout: :gapped_panels)
    panel_count = Installation.num_panels()
    panel_width = Installation.panel_width()
    panel_height = Installation.panel_height()
    installation = Octopus.App.get_installation_info()
    gapped_width =
      installation.panel_count * installation.panel_width +
        (installation.panel_count - 1) * installation.panel_gap

    image = Image.load("landscape_transparent")

    # Hellblauer Hintergrund
    bg = Canvas.new(gapped_width, panel_height)
    bg = Canvas.fill(bg, {100, 180, 255})

    # PNG auf Hintergrund zeichnen (Transparenz wird respektiert)
    canvas = Canvas.overlay(bg, image)

    :timer.send_interval(trunc(1000 / @fps), :tick)
    :timer.send_interval(10_000, :change_acceleration)

    {:ok, %State{canvas: canvas, time: 0, x: 0, acceleration: 0.1, speed: 0}}
  end

  def add_window_corners(canvas) do
    # Use dynamic panel layout instead of hardcoded gap calculation
    display_info = Octopus.App.get_display_info()
    panel_count = display_info.num_panels
    panel_width = display_info.panel_width

    window_locations =
      for panel_id <- 0..(panel_count - 1) do
        {start_x, _end_x} = display_info.panel_range.(panel_id, :x)
        {start_x, 0}
      end

    Enum.reduce(window_locations, canvas, fn {x, y}, canvas ->
      canvas
      |> Canvas.put_pixel({x, y}, {0, 0, 0})
      |> Canvas.put_pixel({x + panel_width - 1, y}, {0, 0, 0})
      |> Canvas.put_pixel({x, y + 7}, {0, 0, 0})
      |> Canvas.put_pixel({x + panel_width - 1, y + 7}, {0, 0, 0})
    end)
  end

  def handle_info(:tick, %State{} = state) do
    canvas2 = state.canvas |> Canvas.translate({trunc(state.x), 0}, true)

    canvas2
    |> add_window_corners()
    |> Octopus.App.update_display()

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

  def handle_event(
        %InputEvent{type: :joystick, joystick: _joystick, direction: :left},
        state
      ) do
    # Go forward (left moves landscape right)
    state = %State{state | acceleration: 0.1}
    {:noreply, state}
  end

  def handle_event(
        %InputEvent{type: :joystick, joystick: _joystick, direction: :right},
        state
      ) do
    # Go backward (right moves landscape left)
    state = %State{state | acceleration: -0.1}
    {:noreply, state}
  end

  def handle_event(
        %InputEvent{type: :joystick, joystick: _joystick, direction: :center},
        state
      ) do
    # Stop accelerating
    state = %State{state | acceleration: 0}
    {:noreply, state}
  end

  def handle_event(%InputEvent{}, state) do
    {:noreply, state}
  end

  def handle_event(_, state) do
    {:noreply, state}
  end
end
