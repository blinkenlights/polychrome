defmodule Octopus.Animation do
  alias Octopus.Canvas

  @moduledoc """
  Functional animation system for canvas transitions.

  Provides pure functions for creating and stepping through animations.
  Each animation is a data structure that can be stepped with a delta time.
  """

  defmodule Animation do
    @moduledoc """
    Represents an animation with its current state.
    """
    defstruct type: nil,
              start_canvas: nil,
              end_canvas: nil,
              duration: nil,
              elapsed: 0.0,
              easing: nil,
              options: %{}
  end

  @doc """
  Steps an animation forward by the given delta time.

  Returns `{canvas, animation}` where canvas is the current state
  and animation is the updated animation (or nil if complete).
  """
  def step(%Animation{} = animation, dt) do
    new_elapsed = animation.elapsed + dt
    progress = min(new_elapsed / animation.duration, 1.0)

    canvas = interpolate(animation, progress)

    if progress >= 1.0 do
      {canvas, nil}
    else
      {canvas, %{animation | elapsed: new_elapsed}}
    end
  end

  @doc """
  Checks if an animation is complete.
  """
  def done?(nil), do: true
  def done?(%Animation{}), do: false

  @doc """
  Creates a fade-in animation.

  ## Options
  * `:duration` - Duration in milliseconds [default: 1000]
  * `:easing` - Easing function [default: :linear]
  """
  def fade_in(canvas1, canvas2, opts \\ []) do
    duration = Keyword.get(opts, :duration, 1000)
    easing = Keyword.get(opts, :easing, :linear)

    %Animation{
      type: :fade,
      start_canvas: canvas1,
      end_canvas: canvas2,
      duration: duration,
      easing: easing
    }
  end

  @doc """
  Creates a fade-out animation.

  ## Options
  * `:duration` - Duration in milliseconds [default: 1000]
  * `:easing` - Easing function [default: :linear]
  """
  def fade_out(canvas1, canvas2, opts \\ []) do
    duration = Keyword.get(opts, :duration, 1000)
    easing = Keyword.get(opts, :easing, :linear)

    %Animation{
      type: :fade,
      start_canvas: canvas1,
      end_canvas: canvas2,
      duration: duration,
      easing: easing
    }
  end

  @doc """
  Creates a slide-in animation.

  ## Options
  * `:from` - Direction to slide from (`:left`, `:right`, `:top`, `:bottom`) [default: `:left`]
  * `:duration` - Duration in milliseconds [default: 1000]
  * `:easing` - Easing function [default: :ease_out]
  """
  def slide_in(canvas1, canvas2, opts \\ []) do
    from = Keyword.get(opts, :from, :left)
    duration = Keyword.get(opts, :duration, 1000)
    easing = Keyword.get(opts, :easing, :ease_out)

    %Animation{
      type: :slide,
      start_canvas: canvas1,
      end_canvas: canvas2,
      duration: duration,
      easing: easing,
      options: %{direction: from}
    }
  end

  @doc """
  Creates a push transition between two canvases.

  ## Options
  * `:direction` - Push direction (`:left`, `:right`, `:top`, `:bottom`) [default: `:left`]
  * `:duration` - Duration in milliseconds [default: 1000]
  * `:easing` - Easing function [default: :ease_in_out]
  * `:separation` - Pixels between canvases [default: 0]
  """
  def push(canvas1, canvas2, opts \\ []) do
    direction = Keyword.get(opts, :direction, :left)
    duration = Keyword.get(opts, :duration, 1000)
    easing = Keyword.get(opts, :easing, :ease_in_out)
    separation = Keyword.get(opts, :separation, 0)

    %Animation{
      type: :push,
      start_canvas: canvas1,
      end_canvas: canvas2,
      duration: duration,
      easing: easing,
      options: %{direction: direction, separation: separation}
    }
  end

  @doc """
  Creates a crossfade transition between two canvases.

  ## Options
  * `:duration` - Duration in milliseconds [default: 1000]
  * `:easing` - Easing function [default: :ease_in_out]
  """
  def crossfade(canvas1, canvas2, opts \\ []) do
    duration = Keyword.get(opts, :duration, 1000)
    easing = Keyword.get(opts, :easing, :ease_in_out)

    %Animation{
      type: :crossfade,
      start_canvas: canvas1,
      end_canvas: canvas2,
      duration: duration,
      easing: easing
    }
  end

  @doc """
  Creates a sequence of animations that play one after another.

  The duration is the total duration for all animations combined.
  """
  def sequence(animations, opts \\ []) do
    duration = Keyword.get(opts, :duration, 1000)
    easing = Keyword.get(opts, :easing, :linear)

    %Animation{
      type: :sequence,
      start_canvas: List.first(animations).start_canvas,
      end_canvas: List.last(animations).end_canvas,
      duration: duration,
      easing: easing,
      options: %{animations: animations}
    }
  end

  defp interpolate(%Animation{type: :fade} = animation, progress) do
    eased_progress = apply_easing(progress, animation.easing)
    Canvas.blend(animation.end_canvas, animation.start_canvas, :add, eased_progress)
  end

  defp interpolate(%Animation{type: :slide} = animation, progress) do
    eased_progress = apply_easing(progress, animation.easing)
    direction = animation.options.direction

    case direction do
      :left -> slide_interpolate_horizontal(animation, eased_progress, :left)
      :right -> slide_interpolate_horizontal(animation, eased_progress, :right)
      :top -> slide_interpolate_vertical(animation, eased_progress, :top)
      :bottom -> slide_interpolate_vertical(animation, eased_progress, :bottom)
    end
  end

  defp interpolate(%Animation{type: :push} = animation, progress) do
    eased_progress = apply_easing(progress, animation.easing)
    direction = animation.options.direction
    separation = animation.options.separation

    push_interpolate(animation, eased_progress, direction, separation)
  end

  defp interpolate(%Animation{type: :crossfade} = animation, progress) do
    eased_progress = apply_easing(progress, animation.easing)
    # For crossfade, we blend the end canvas over the start canvas
    Canvas.blend(animation.end_canvas, animation.start_canvas, :add, eased_progress)
  end

  defp interpolate(%Animation{type: :sequence} = animation, progress) do
    animations = animation.options.animations
    total_animations = length(animations)
    animation_index = trunc(progress * total_animations)

    if animation_index >= total_animations do
      # Return the last animation's end canvas
      List.last(animations).end_canvas
    else
      # Calculate progress within the current animation
      local_progress = progress * total_animations - animation_index
      current_animation = Enum.at(animations, animation_index)

      # Step the current animation
      {canvas, _} =
        step(%{current_animation | elapsed: local_progress * current_animation.duration}, 0)

      canvas
    end
  end

  defp slide_interpolate_horizontal(animation, progress, direction) do
    canvas = animation.end_canvas
    slide_distance = trunc(progress * canvas.width)

    case direction do
      :left ->
        # Slide from left to right
        left_canvas =
          Canvas.cut(
            canvas,
            {canvas.width - slide_distance, 0},
            {canvas.width - 1, canvas.height - 1}
          )

        right_canvas = Canvas.new(slide_distance, canvas.height)
        Canvas.join(left_canvas, right_canvas, direction: :horizontal)

      :right ->
        # Slide from right to left
        left_canvas = Canvas.new(slide_distance, canvas.height)

        right_canvas =
          Canvas.cut(canvas, {0, 0}, {canvas.width - slide_distance - 1, canvas.height - 1})

        Canvas.join(left_canvas, right_canvas, direction: :horizontal)
    end
  end

  defp slide_interpolate_vertical(animation, progress, direction) do
    canvas = animation.end_canvas
    slide_distance = trunc(progress * canvas.height)

    case direction do
      :top ->
        # Slide from top to bottom
        top_canvas =
          Canvas.cut(
            canvas,
            {0, canvas.height - slide_distance},
            {canvas.width - 1, canvas.height - 1}
          )

        bottom_canvas = Canvas.new(canvas.width, slide_distance)
        Canvas.join(top_canvas, bottom_canvas, direction: :vertical)

      :bottom ->
        # Slide from bottom to top
        top_canvas = Canvas.new(canvas.width, slide_distance)

        bottom_canvas =
          Canvas.cut(canvas, {0, 0}, {canvas.width - 1, canvas.height - slide_distance - 1})

        Canvas.join(top_canvas, bottom_canvas, direction: :vertical)
    end
  end

  defp push_interpolate(animation, progress, direction, separation) do
    canvas1 = animation.start_canvas
    canvas2 = animation.end_canvas

    canvas =
      case direction do
        :up ->
          Canvas.join(canvas1, canvas2, direction: :vertical, separation: separation)

        :down ->
          Canvas.join(canvas2, canvas1, direction: :vertical, separation: separation)

        :left ->
          Canvas.join(canvas1, canvas2, direction: :horizontal, separation: separation)

        :right ->
          Canvas.join(canvas2, canvas1, direction: :horizontal, separation: separation)
      end

    {initial_x, initial_y} =
      case direction do
        :up ->
          {0, 0}

        :down ->
          {0, canvas1.height + separation}

        :left ->
          {0, 0}

        :right ->
          {canvas1.width + separation, 0}
      end

    {final_x, final_y} =
      case direction do
        :up ->
          {0, canvas1.height + separation}

        :down ->
          {0, 0}

        :left ->
          {canvas2.width + separation, 0}

        :right ->
          nil
      end

    distance_x = final_x - initial_x - 1
    distance_y = final_y - initial_y - 1

    top_left = {
      initial_x + trunc(progress * distance_x),
      initial_y + trunc(progress * distance_y)
    }

    bottom_right = {
      initial_x + trunc(progress * distance_x) - 1 + canvas2.width,
      initial_y + trunc(progress * distance_y) - 1 + canvas2.height
    }

    Canvas.crop(
      canvas,
      top_left,
      bottom_right
    )

    # case direction do
    #   :up ->
    #     total_distance = canvas2.height + separation
    #     current_position = total_distance - trunc(progress * total_distance) - 1

    #     Canvas.join(canvas1, canvas2, direction: :vertical, separation: separation)
    #     |> Canvas.crop(
    #       {0, current_position},
    #       {canvas1.width - 1, current_position + canvas1.height + separation}
    #     )

    #   :down ->
    #     total_distance = canvas2.height + separation + 1
    #     current_position = total_distance - trunc(progress * total_distance) - 1

    #     Canvas.join(canvas2, canvas1, direction: :vertical, separation: separation)
    #     |> Canvas.crop(
    #       {0, current_position},
    #       {canvas1.width - 1, current_position + canvas1.height + separation}
    #     )
    # end
  end

  defp apply_easing(progress, :linear), do: progress
  defp apply_easing(progress, :ease_in), do: progress * progress
  defp apply_easing(progress, :ease_out), do: 1 - (1 - progress) * (1 - progress)

  defp apply_easing(progress, :ease_in_out) do
    if progress < 0.5 do
      2 * progress * progress
    else
      1 - 2 * (1 - progress) * (1 - progress)
    end
  end

  defp apply_easing(progress, :ease_out_back) do
    c1 = 1.70158
    c3 = c1 + 1
    1 + c3 * :math.pow(progress - 1, 3) + c1 * :math.pow(progress - 1, 2)
  end

  defp apply_easing(progress, easing_fun) when is_function(easing_fun), do: easing_fun.(progress)
end
