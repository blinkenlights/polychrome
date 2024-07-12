defmodule Octopus.Apps.AnimatorTest do
  use Octopus.App, category: :test
  require Logger

  alias Octopus.Canvas
  alias Octopus.{Animator, Font, Transitions}

  def name(), do: "Animator Test"

  def init(_args) do
    :timer.send_interval(750, self(), :tick)
    {:ok, animator} = Animator.start_link(get_app_id())

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
    direction = Enum.random([:left, :right, :top, :bottom])
    # separation = Enum.random(1..5)
    separation = 3

    transition_fun =
      &Transitions.push(&1, &2, direction: direction, steps: 60, separation: separation)

    Animator.start_animation(state.animator, canvas, {pos_x, 0}, transition_fun, 1500)

    {:noreply, state}
  end
end
