defmodule Octopus.Apps.Diamonds do
  use Octopus.App, category: :interactive
  require Logger

  alias Octopus.Canvas
  alias Octopus.WebP
  alias Octopus.Events.Event.Proximity, as: ProximityEvent

  defmodule State do
    defstruct [:panel_events, :diamond_animation]
  end

  @fps 60
  @frame_time_ms trunc(1000 / @fps)

  @diamond_duration_ms 5_000

  def name(), do: "💠 Diamonds"

  def app_init(_) do
    Octopus.App.configure_display(layout: :adjacent_panels)
    :timer.send_interval(@frame_time_ms, :tick)

    diamond_animation = WebP.load_animation("ruby")

    {:ok, %State{panel_events: %{}, diamond_animation: diamond_animation}}
  end

  def handle_event(%ProximityEvent{} = event, state) do
    # Store the last proximity event for each panel (not panel+sensor)
    key = event.panel
    state = %State{state | panel_events: Map.put(state.panel_events, key, event)}

    {:noreply, state}
  end

  def handle_event(_any_event, state) do
    {:noreply, state}
  end

  def handle_info(:tick, state) do
    display_info = Octopus.App.get_display_info()
    canvas = Canvas.new(display_info.width, display_info.height)
    current_time = System.os_time(:millisecond)

    # For each panel, check if it should show animation or be hidden due to recent proximity
    canvas =
      for panel_index <- 1..get_panel_count(display_info), reduce: canvas do
        acc_canvas ->
          case Map.get(state.panel_events, panel_index) do
            event when current_time - event.timestamp < @diamond_duration_ms ->
              acc_canvas

            _ ->
              render_diamond(
                acc_canvas,
                display_info,
                panel_index,
                state.diamond_animation,
                current_time
              )
          end
      end

    Octopus.App.update_display(canvas)

    {:noreply, state}
  end

  def handle_info(_any_info, state) do
    {:noreply, state}
  end

  defp render_diamond(canvas, display_info, panel_index, diamond_animation, time) do
    # Calculate animation frame based on time since event
    animation_length = length(diamond_animation)

    if animation_length > 0 do
      # Calculate which frame to show based on time elapsed
      total_animation_duration =
        Enum.reduce(diamond_animation, 0, fn {_, duration}, acc -> acc + duration end)

      # Loop the animation during the diamond duration
      animation_time = rem(time, total_animation_duration)

      # Find the correct frame
      {frame_canvas, _} = get_animation_frame(diamond_animation, animation_time)

      # Calculate position for this panel
      panel_start_x = (panel_index - 1) * display_info.panel_width

      # Center the diamond animation on the panel
      x_offset = panel_start_x + div(display_info.panel_width - frame_canvas.width, 2)
      y_offset = div(display_info.panel_height - frame_canvas.height, 2)

      # Ensure the diamond fits within the panel bounds
      x_offset =
        max(
          panel_start_x,
          min(x_offset, panel_start_x + display_info.panel_width - frame_canvas.width)
        )

      y_offset = max(0, min(y_offset, display_info.panel_height - frame_canvas.height))

      Canvas.overlay(canvas, frame_canvas, offset: {x_offset, y_offset})
    else
      canvas
    end
  end

  defp get_animation_frame(animation, target_time) do
    get_animation_frame(animation, target_time, 0)
  end

  defp get_animation_frame([{canvas, duration} | rest], target_time, accumulated_time) do
    if target_time <= accumulated_time + duration do
      {canvas, duration}
    else
      get_animation_frame(rest, target_time, accumulated_time + duration)
    end
  end

  defp get_animation_frame([], _target_time, _accumulated_time) do
    # Fallback to first frame if something goes wrong
    {Canvas.new(8, 8), 100}
  end

  defp get_panel_count(display_info) do
    div(display_info.width, display_info.panel_width)
  end
end
