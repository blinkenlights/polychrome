defmodule Octopus.Apps.AnimationDemo do
  use Octopus.App, category: :animation
  require Logger

  alias Octopus.{Canvas, Animation}

  defmodule State do
    defstruct [:current_animation, :animation_type, :canvas1, :canvas2, :time]
  end

  @fps 60

  def name(), do: "Animation Demo"

  def app_init(_args) do
    Octopus.App.configure_display(layout: :gapped_panels)
    display_info = Octopus.App.get_display_info()

    canvas1 =
      Canvas.new(display_info.panel_width, display_info.panel_height) |> Canvas.fill({255, 0, 0})

    canvas2 =
      Canvas.new(display_info.panel_width, display_info.panel_height)
      |> Canvas.fill({255, 255, 0})

    # Start with a fade-in animation
    animation =
      Animation.push(canvas1, canvas2, duration: 2000, easing: :ease_out, direction: :down)

    state = %State{
      current_animation: animation,
      animation_type: :push_down,
      canvas1: canvas1,
      canvas2: canvas2,
      time: 0
    }

    Octopus.App.update_display(canvas1)
    :timer.send_interval(trunc(1000 / @fps), :tick)

    {:ok, state}
  end

  def handle_info(:tick, %State{} = state) do
    # Convert to milliseconds
    dt = 1000 / @fps

    if Animation.done?(state.current_animation) do
      # Animation complete, start next one
      {new_animation, new_type} = next_animation(state)

      {:noreply,
       %State{
         state
         | current_animation: new_animation,
           animation_type: new_type,
           time: state.time + dt
       }}
    else
      # Step the current animation
      {canvas, updated_animation} = Animation.step(state.current_animation, dt)

      Octopus.App.update_display(canvas)

      {:noreply, %State{state | current_animation: updated_animation, time: state.time + dt}}
    end
  end

  def handle_event(%Octopus.Events.Event.Input{type: :button, action: :press, button: 1}, state) do
    # Button 1: Skip to next animation
    {new_animation, new_type} = next_animation(state)

    {:noreply, %State{state | current_animation: new_animation, animation_type: new_type}}
  end

  def handle_event(%Octopus.Events.Event.Input{type: :button, action: :press, button: 2}, state) do
    # Button 2: Toggle between canvas1 and canvas2
    {canvas1, canvas2} = {state.canvas2, state.canvas1}
    animation = Animation.crossfade(canvas1, canvas2, duration: 1000, easing: :ease_in_out)

    {:noreply,
     %State{
       state
       | current_animation: animation,
         animation_type: :crossfade,
         canvas1: canvas1,
         canvas2: canvas2
     }}
  end

  def handle_event(_event, state) do
    {:noreply, state}
  end

  defp next_animation(state) do
    dbg(state.animation_type)

    case state.animation_type do
      _ ->
        {Animation.push(state.canvas1, state.canvas2,
           duration: 2000,
           easing: :ease_in_out,
           direction: :up
         ), :push_up}

        # :push_up ->
        #   {Animation.push(state.canvas1, state.canvas2,
        #      duration: 2000,
        #      easing: :ease_in_out,
        #      direction: :down
        #    ), :push_down}
    end
  end
end
