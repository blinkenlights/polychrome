defmodule Octopus.Animator do
  use GenServer
  require Logger
  alias Octopus.Canvas

  # todo
  # collision detection
  # easing fun

  @moduledoc """
    Single-use animators for transitions between static frames. Each animator
    handles one animation and terminates when complete. Uses animation_id for
    tracking instead of PIDs.
  """

  # Global registry to track active animators by animation_id
  @registry_name Octopus.Animator

  defmodule State do
    defstruct canvas: nil,
              app_pid: nil,
              animation: nil,
              canvas_size: nil,
              frame_rate: 60,
              animation_id: nil,
              timer_ref: nil
  end

  defmodule Animation do
    defstruct steps: nil,
              start_time: nil,
              position: nil,
              duration: nil,
              easing_fun: nil
  end

  @doc """
    Starts a single-use animation. Returns immediately without exposing GenServer details.

    Parameters:
      * `animation_id` - unique identifier for this animation (required)
      * `app_pid` - the PID of the app process to send canvas updates to (defaults to calling process)
      * `canvas` - the target canvas to animate to (required)
      * `position` - position {x, y} within the animator's canvas (required)
      * `transition_fun` - function that creates animation steps (required)
      * `duration` - animation duration in milliseconds (required)
      * `canvas_size` - tuple {width, height} for the canvas size (required)
      * `frame_rate` - frames per second for animation updates (defaults to 60)
      * `easing_fun` - easing function for animation timing (defaults to linear)
  """
  def animate(opts) do
    animation_id = Keyword.fetch!(opts, :animation_id)
    app_pid = Keyword.get(opts, :app_pid, self())
    canvas = Keyword.fetch!(opts, :canvas)
    position = Keyword.fetch!(opts, :position)
    transition_fun = Keyword.fetch!(opts, :transition_fun)
    duration = Keyword.fetch!(opts, :duration)
    canvas_size = Keyword.fetch!(opts, :canvas_size)
    frame_rate = Keyword.get(opts, :frame_rate, 60)
    easing_fun = Keyword.get(opts, :easing_fun, & &1)

    # Start the GenServer
    {:ok, pid} =
      GenServer.start_link(__MODULE__, %{
        animation_id: animation_id,
        app_pid: app_pid,
        canvas_size: canvas_size,
        frame_rate: frame_rate
      })

    # Wait for the GenServer to register itself and start the animation
    GenServer.call(
      pid,
      {:start_animation, {canvas, position, transition_fun, duration, easing_fun}}
    )

    :ok
  end

  @doc """
    Clears an animation by animation_id. Safe to call on completed animations.
  """
  def clear(animation_id) do
    case Registry.lookup(@registry_name, animation_id) do
      [{pid, _}] when is_pid(pid) ->
        if Process.alive?(pid) do
          GenServer.cast(pid, :clear)
        end

        :ok

      [] ->
        # Animation already completed or never existed
        :ok
    end
  end

  def init(opts) do
    animation_id = opts.animation_id
    app_pid = opts.app_pid
    canvas_size = opts.canvas_size
    frame_rate = opts.frame_rate

    # Register this process with the animation_id
    Registry.register(@registry_name, animation_id, nil)

    {width, height} = canvas_size

    state = %State{
      animation_id: animation_id,
      canvas: Canvas.new(width, height),
      app_pid: app_pid,
      canvas_size: canvas_size,
      frame_rate: frame_rate
    }

    {:ok, state}
  end

  def handle_call(
        {:start_animation, {target_canvas, {pos_x, pos_y}, animation_fun, duration, easing_fun}},
        _from,
        %State{} = state
      ) do
    current_canvas =
      Canvas.cut(
        state.canvas,
        {pos_x, pos_y},
        {pos_x + target_canvas.width - 1, pos_y + target_canvas.height - 1}
      )

    start = System.os_time(:millisecond)
    steps = animation_fun.(current_canvas, target_canvas) |> Enum.to_list()

    animation = %Animation{
      steps: steps,
      start_time: start,
      position: {pos_x, pos_y},
      duration: duration,
      easing_fun: easing_fun
    }

    # Start the animation timer
    tick_interval_ms = (1000 / state.frame_rate) |> trunc
    timer_ref = :timer.send_interval(tick_interval_ms, self(), :tick)

    {:reply, :ok, %State{state | animation: animation, timer_ref: timer_ref}}
  end

  def handle_cast(:clear, state) do
    # Send final blank canvas
    {width, height} = state.canvas_size
    blank_canvas = Canvas.new(width, height)
    send(state.app_pid, {:animator_update, state.animation_id, blank_canvas, :final})

    {:stop, :normal, state}
  end

  def handle_info(:tick, %State{animation: nil} = state) do
    # No animation running, shouldn't happen but handle gracefully
    {:stop, :normal, state}
  end

  def handle_info(:tick, %State{animation: animation} = state) do
    now = System.os_time(:millisecond)

    total_steps = animation.steps |> length()
    progress = min((now - animation.start_time) / animation.duration, 1.0)
    index = round(animation.easing_fun.(progress) * (total_steps - 1))

    current_canvas = Enum.at(animation.steps, index)
    {pos_x, pos_y} = animation.position

    # Overlay on the animator's canvas
    canvas = Canvas.overlay(state.canvas, current_canvas, offset: {pos_x, pos_y})

    # Check if this is the final frame
    is_final = animation.start_time + animation.duration <= now
    frame_status = if is_final, do: :final, else: :in_progress

    # Send update to app
    send(state.app_pid, {:animator_update, state.animation_id, canvas, frame_status})

    if is_final do
      # Animation complete, terminate
      {:stop, :normal, %State{state | canvas: canvas}}
    else
      {:noreply, %State{state | canvas: canvas}}
    end
  end

  def terminate(_reason, state) do
    # Clean up timer if it exists
    if state.timer_ref do
      :timer.cancel(state.timer_ref)
    end

    # Unregister from global registry
    Registry.unregister(@registry_name, state.animation_id)

    :ok
  end
end
