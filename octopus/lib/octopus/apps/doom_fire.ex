defmodule Octopus.Apps.DoomFire do
  use Octopus.App, category: :animation

  alias Octopus.WebP
  alias Octopus.Canvas

  defmodule Fire do
    defstruct [:width, :height, :buffer]

    alias Octopus.Canvas

    def new(width, height) do
      buffer = for y <- 0..(height - 1), x <- 0..(width - 1), into: %{}, do: {{x, y}, 0}
      %__MODULE__{width: width, height: height, buffer: buffer}
    end

    def step(%__MODULE__{width: width, height: height, buffer: buffer}) do
      buffer = for x <- 0..(width - 1), into: buffer, do: {{x, height - 1}, :rand.uniform(4) + 11}

      buffer =
        for y <- 0..(height - 2), x <- 0..(width - 1), into: buffer do
          random_offset = :rand.uniform(3) - 2
          dst_x = min(max(x + random_offset, 0), width - 1)
          value = max(Map.get(buffer, {dst_x, y + 1}) - :rand.uniform(3) - 1, 0)
          {{x, y}, value}
        end

      %__MODULE__{width: width, height: height, buffer: buffer}
    end

    def stream(width, height) do
      Stream.unfold(new(width, height), &{&1, step(&1)})
    end

    def draw(%__MODULE__{width: width, height: height, buffer: buffer}, %Canvas{} = canvas) do
      for y <- 0..(height - 1), x <- 0..(width - 1), into: canvas do
        value = Map.get(buffer, {x, y})
        {{x, y}, intensity_to_rgb(value)}
      end
    end

    defp intensity_to_rgb(intensity) do
      case intensity do
        0 ->
          {0, 0, 0}

        1 ->
          {220, 0, 0}

        n when n <= 8 ->
          fraction = (n - 1) / 7
          {220, trunc(fraction * 220), 0}

        n ->
          fraction = (n - 8) / 7
          {220, 220, trunc(fraction * 220)}
      end
    end
  end

  def name, do: "Doom Fire"
  def icon, do: WebP.load("doom-fire")

  def list_modes do
    [
      %{
        id: "default",
        name: "default",
        accent_color: "#E74C3C",
        summary: "Classic doom fire",
        builtin: true
      }
    ]
  end

  def mode_config("default"), do: %{}
  def mode_config(_), do: %{}

  def app_init(_) do
    # Configure display using new unified API - adjacent layout (was Canvas.to_frame())
    Octopus.App.configure_display(layout: :adjacent_panels)

    # Subscribe to global parameter changes
    Octopus.Params.Global.subscribe()

    # Read initial global speed value
    global_speed = Octopus.Params.Global.speed()

    # Get dimensions from display info instead of installation
    display_info = Octopus.App.get_display_info()
    width = display_info.width
    height = display_info.height

    :timer.send_interval(trunc(1000 / 10), :tick)

    {:ok,
     %{
       fire: Fire.new(width, height),
       canvas: Canvas.new(width, height),
       global_speed: global_speed,
       last_update: :erlang.monotonic_time(:millisecond)
     }}
  end

  def handle_info({:param_updated, :speed, new_value}, state) do
    # Global speed parameter changed - update stored value
    {:noreply, %{state | global_speed: new_value}}
  end

  def handle_info({:param_updated, _key, _value}, state) do
    # Other global parameters changed - ignore
    {:noreply, state}
  end

  def handle_info(
        :tick,
        %{fire: fire, canvas: canvas, global_speed: global_speed, last_update: last_update} =
          state
      ) do
    current_time = :erlang.monotonic_time(:millisecond)
    time_since_last = current_time - last_update

    # Apply global speed - only update fire if enough time has passed based on speed
    # Base interval is 100ms (10 FPS), with 10% influence from global speed
    speed_factor = 0.9 + 0.1 * global_speed
    target_interval = trunc(100 / speed_factor)

    {fire, last_update} =
      if time_since_last >= target_interval do
        {Fire.step(fire), current_time}
      else
        {fire, last_update}
      end

    canvas = Canvas.clear(canvas)
    canvas = Fire.draw(fire, canvas)
    Octopus.App.update_display(canvas)
    {:noreply, %{state | fire: fire, canvas: canvas, last_update: last_update}}
  end
end
