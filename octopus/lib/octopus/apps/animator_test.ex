defmodule Octopus.Apps.AnimatorTest do
  use Octopus.App, category: :test

  alias Octopus.Canvas
  alias Octopus.{Animator, Font, Transitions}

  def name(), do: "Animator Test"

  def app_init(_args) do
    # Configure display using modern unified API
    Octopus.App.configure_display(layout: :adjacent_panels)

    # Get display info for dynamic sizing
    display_info = Octopus.App.get_display_info()

    :timer.send_interval(300, self(), :tick)

    state = %{
      font: Font.load("ddp-DoDonPachi (Cave)"),
      display_info: display_info,
      animation_counter: 0
    }

    {:ok, state}
  end

  @letters ~c"ABCDEFGHIJKLMNOPQRSTUVWXYZ"
  def handle_info(:tick, %{} = state) do
    canvas = Canvas.new(8, 8)
    canvas = Font.draw_char(state.font, Enum.random(@letters), 0, canvas)

    pos_x = Enum.random([0, 8, 16, 24, 32, 40, 48, 56, 64, 72])
    direction = Enum.random([:left, :right, :top, :bottom])
    easing_fun = &Easing.cubic_out/1

    transition_fun = &Transitions.slide_over(&1, &2, direction: direction)

    # Use new single-call API with unique animation ID
    animation_id = {:test_animation, state.animation_counter}

    Animator.animate(
      animation_id: animation_id,
      app_pid: self(),
      canvas: canvas,
      position: {pos_x, 0},
      transition_fun: transition_fun,
      duration: 500,
      canvas_size: {state.display_info.width, state.display_info.height},
      frame_rate: 60,
      easing_fun: easing_fun
    )

    {:noreply, %{state | animation_counter: state.animation_counter + 1}}
  end

  def handle_info({:animator_update, _animation_id, canvas, _frame_status}, state) do
    # Update display with the animated canvas
    Octopus.App.update_display(canvas, :rgb, easing_interval: 0)
    {:noreply, state}
  end
end
