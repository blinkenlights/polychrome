defmodule Octopus.Animator do
  use GenServer
  require Logger
  alias Octopus.{Canvas, Mixer}

  # todo
  # collision detection
  # easing fun

  @frame_rate 60
  @canvas_size_x 80
  @canvas_size_y 8

  @moduledoc """
    Animates transistions between static frages. Sends out streams of frames to the mixer.
  """
  defmodule State do
    defstruct canvas: nil,
              app_id: nil,
              animations: %{}
  end

  defmodule Animation do
    defstruct steps: nil,
              position: nil,
              duration: nil,
              easing_fun: nil
  end

  @doc """
    Starts the animator.

    Parameters:
      * `app_id` - the app_id to use when sending frames to the mixer
  """

  def start_link(app_id) when is_binary(app_id) do
    GenServer.start_link(__MODULE__, app_id)
  end

  @doc """
    Adds an animation to the animator.

    Parameters:
      * `canvas` - the canvas to transition to
      *  positon - of the the top left pixel {x, y}
      * `animation_fun` - The transition function to use. Should take two canvases and return a list of canvases.
      * `duration` - The duration of the animation in milliseconds.

    Options:
      * `easing_fun` - The easing function to use. It uses floats between 0 and 1. [default: fn x -> x end]
  """

  def start_animation(
        pid,
        %Canvas{} = canvas,
        position = {_, _},
        animation_fun,
        duration,
        opts \\ []
      )
      when is_pid(pid) and is_function(animation_fun) do
    easing_fun = Keyword.get(opts, :easing_fun, & &1)

    GenServer.cast(
      pid,
      {:start_animation, {canvas, position, animation_fun, duration, easing_fun}}
    )
  end

  def init(app_id) when is_binary(app_id) do
    state = %State{
      canvas: Canvas.new(@canvas_size_x, @canvas_size_y),
      app_id: app_id
    }

    :timer.send_interval((1000 / @frame_rate) |> trunc, self(), :tick)

    {:ok, state}
  end

  def handle_cast(
        {:start_animation, {target_canvas, {pos_x, pos_y}, animation_fun, duration, easing_fun}},
        state
      ) do
    current_canvas =
      Canvas.cut(
        state.canvas,
        {pos_x, pos_y},
        {pos_x + target_canvas.width - 1, pos_y + target_canvas.height - 1}
      )

    start = System.os_time(:millisecond)
    steps = animation_fun.(current_canvas, target_canvas) |> Enum.to_list()

    animation =
      %Animation{
        steps: steps,
        position: {pos_x, pos_y},
        duration: duration,
        easing_fun: easing_fun
      }

    {:noreply, %State{state | animations: Map.put(state.animations, start, animation)}}
  end

  def handle_info(:tick, %State{animations: %{} = animations} = state) do
    now = System.os_time(:millisecond)

    canvas =
      animations
      |> Enum.sort_by(fn {start, _} -> start end)
      |> Enum.map(fn {start, %Animation{} = animation} ->
        total_steps = animation.steps |> length()
        progress = min((now - start) / animation.duration, 1)
        index = round(animation.easing_fun.(progress) * (total_steps - 1))
        canvas = Enum.at(animation.steps, index)
        {animation.position, canvas}
      end)
      |> Enum.reduce(state.canvas, fn {{x, y}, canvas}, canvas_acc ->
        Canvas.overlay(canvas_acc, canvas, offset: {x, y})
      end)

    frame = Canvas.to_frame(canvas, easing_interval: 50)
    Mixer.handle_frame(state.app_id, frame)

    # filter out animations that are done
    animations =
      animations
      |> Enum.reject(fn {start, %Animation{duration: duration}} ->
        start + duration < now
      end)
      |> Enum.into(%{})

    {:noreply, %State{state | animations: animations, canvas: canvas}}
  end
end
