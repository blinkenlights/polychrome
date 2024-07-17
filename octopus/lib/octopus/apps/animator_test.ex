defmodule Octopus.Apps.AnimatorTest do
  use Octopus.App, category: :test
  require Logger

  alias Octopus.Canvas
  alias Octopus.{Animator, Font, Transitions}

  def name(), do: "Animator Test"

  def init(_args) do
    :timer.send_interval(300, self(), :tick)
    {:ok, animator} = Animator.start_link(app_id: get_app_id())

    state = %{
      animator: animator,
      font: Font.load("ddp-DoDonPachi (Cave)")
    }

    {:ok, state}
  end

  @letters ~c"ABCDEFGHIJKLMNOPQRSTUVWXYZ"
  def handle_info(:tick, %{} = state) do
    canvas = Canvas.new(8, 8)
    canvas = Font.draw_char(state.font, Enum.random(@letters), 0, canvas)

    pos_x = Enum.random([0, 8, 16, 24, 32, 40, 48, 56, 64, 72])
    # pos_x = 8
    direction = Enum.random([:left, :right, :top, :bottom])
    easing_fun = &Easing.cubic_out/1

    # separation = Enum.random(1..5)
    transition_fun =
      &Transitions.push(&1, &2, direction: direction, steps: 8)

    # transition_fun = &Transitions.slide_over(&1, &2, direction: direction)

    Animator.start_animation(state.animator, canvas, {pos_x, 0}, transition_fun, 500,
      easing_fun: easing_fun
    )

    {:noreply, state}
  end
end
