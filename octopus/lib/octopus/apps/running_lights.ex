defmodule Octopus.Apps.RunningLights do
  use Octopus.App, category: :animation

  alias Octopus.Canvas
  alias Octopus.Events.Event.Lifecycle, as: LifecycleEvent

  # One strip pixel every 100ms — same overall speed as before.
  @strip_duration_ms 100
  @tick_ms 10
  @position_step @tick_ms / @strip_duration_ms

  # Virtual light radius in panel pixels — controls how far brightness spreads.
  @light_radius 5.0

  # Full hue cycle duration — slow, steady color drift.
  @hue_cycle_duration_ms 30_000
  @hue_step 360 * @tick_ms / @hue_cycle_duration_ms

  defmodule State do
    defstruct [:position, :direction, :hue, :display_info, :global_speed]
  end

  def name(), do: "Running Lights"

  def compatible?() do
    installation = Octopus.App.get_installation_info()

    installation.panel_count >= 1 and
      (installation.panel_width == 1 or installation.panel_height == 1)
  end

  def app_init(_args) do
    Octopus.App.configure_display(layout: :gapped_panels)
    Octopus.Params.Global.subscribe()

    display_info = Octopus.App.get_display_info()
    global_speed = Octopus.Params.Global.speed()

    state = %State{
      position: 0.0,
      direction: 1.0,
      hue: 0.0,
      display_info: display_info,
      global_speed: global_speed
    }

    render(state)
    schedule_tick()

    {:ok, state}
  end

  def handle_event(%LifecycleEvent{type: :app_selected}, state) do
    render(state)
    schedule_tick()
    {:noreply, state}
  end

  def handle_event(_, state), do: {:noreply, state}

  def handle_info({:param_updated, :speed, global_speed}, %State{} = state) do
    {:noreply, %{state | global_speed: global_speed}}
  end

  def handle_info({:param_updated, _, _}, %State{} = state), do: {:noreply, state}

  def handle_info(:tick, %State{} = state) do
    last = strip_length(state.display_info) - 1
    position_step = @position_step * state.global_speed
    hue_step = @hue_step * state.global_speed
    next_position = state.position + state.direction * position_step

    {position, direction} = bounce(next_position, state.direction, last)
    hue = :math.fmod(state.hue + hue_step, 360.0)

    state = %State{state | position: position, direction: direction, hue: hue}
    render(state)
    schedule_tick()

    {:noreply, state}
  end

  defp schedule_tick(), do: :timer.send_after(@tick_ms, :tick)

  defp bounce(_position, direction, last) when last == 0, do: {0.0, direction}

  defp bounce(position, direction, last) do
    cond do
      position > last ->
        overshoot = position - last
        {last - overshoot, -direction}

      position < 0 ->
        {-position, -direction}

      true ->
        {position, direction}
    end
  end

  defp render(%State{} = state) do
    canvas = Canvas.new(state.display_info.width, state.display_info.height)
    {r, g, b} = hue_to_rgb(state.hue)
    radius = ceil(@light_radius)
    last = strip_length(state.display_info) - 1
    first = max(trunc(state.position) - radius, 0)
    last = min(trunc(state.position) + radius, last)

    canvas =
      for panel_id <- 0..(state.display_info.num_panels - 1),
          local_coord <- first..last,
          reduce: canvas do
        canvas ->
          intensity = falloff(abs(local_coord - state.position))

          if intensity > 0 do
            color = {trunc(r * intensity), trunc(g * intensity), trunc(b * intensity)}
            {local_x, local_y} = strip_coords(state.display_info, local_coord)

            case state.display_info.panel_to_global_coords.(panel_id, local_x, local_y) do
              :invalid_panel -> canvas
              {x, y} -> Canvas.put_pixel(canvas, {x, y}, color)
            end
          else
            canvas
          end
      end

    Octopus.App.update_display(canvas)
  end

  defp strip_length(%{panel_width: panel_width, panel_height: panel_height}) do
    max(panel_width, panel_height)
  end

  defp strip_coords(%{panel_width: panel_width, panel_height: panel_height}, coord) do
    if panel_width >= panel_height do
      {coord, 0}
    else
      {0, coord}
    end
  end

  defp falloff(distance) when distance >= @light_radius, do: 0.0

  defp falloff(distance) do
    t = 1 - distance / @light_radius
    t * t * (3 - 2 * t)
  end

  defp hue_to_rgb(hue) do
    %Chameleon.RGB{r: r, g: g, b: b} =
      hue
      |> Chameleon.HSL.new(100, 50)
      |> Chameleon.convert(Chameleon.RGB)

    {r, g, b}
  end
end
