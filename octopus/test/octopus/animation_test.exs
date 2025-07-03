defmodule Octopus.AnimationTest do
  use ExUnit.Case
  alias Octopus.{Animation, Canvas}

  test "fade_in creates animation with correct structure" do
    canvas = Canvas.new(10, 10)
    animation = Animation.fade_in(canvas, duration: 500)

    assert animation.type == :fade
    assert animation.duration == 500
    assert animation.elapsed == 0.0
    assert animation.easing == :linear
    assert animation.start_canvas.width == 10
    assert animation.start_canvas.height == 10
    assert animation.end_canvas == canvas
  end

  test "step returns current canvas and updated animation" do
    canvas = Canvas.new(2, 2)
    animation = Animation.fade_in(canvas, duration: 1000)

    {current_canvas, updated_animation} = Animation.step(animation, 500)

    assert is_struct(current_canvas, Canvas)
    assert is_struct(updated_animation, Animation.Animation)
    assert updated_animation.elapsed == 500.0
    assert !Animation.done?(updated_animation)
  end

  test "step returns nil animation when complete" do
    canvas = Canvas.new(2, 2)
    animation = Animation.fade_in(canvas, duration: 1000)

    {_current_canvas, updated_animation} = Animation.step(animation, 1000)

    assert updated_animation == nil
    assert Animation.done?(updated_animation)
  end

  test "done? returns true for nil" do
    assert Animation.done?(nil)
  end

  test "done? returns false for active animation" do
    canvas = Canvas.new(2, 2)
    animation = Animation.fade_in(canvas, duration: 1000)
    assert !Animation.done?(animation)
  end

  test "crossfade creates animation with correct structure" do
    canvas1 = Canvas.new(10, 10)
    canvas2 = Canvas.new(10, 10)
    animation = Animation.crossfade(canvas1, canvas2, duration: 750)

    assert animation.type == :crossfade
    assert animation.duration == 750
    assert animation.start_canvas == canvas1
    assert animation.end_canvas == canvas2
  end

  test "slide_in creates animation with correct structure" do
    canvas = Canvas.new(10, 10)
    animation = Animation.slide_in(canvas, from: :right, duration: 800)

    assert animation.type == :slide
    assert animation.duration == 800
    assert animation.options.direction == :right
  end

  test "push creates animation with correct structure" do
    canvas1 = Canvas.new(10, 10)
    canvas2 = Canvas.new(10, 10)
    animation = Animation.push(canvas1, canvas2, direction: :left, separation: 5)

    assert animation.type == :push
    assert animation.start_canvas == canvas1
    assert animation.end_canvas == canvas2
    assert animation.options.direction == :left
    assert animation.options.separation == 5
  end
end
