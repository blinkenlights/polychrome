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

  def init(_) do
    :timer.send_interval(trunc(1000 / 10), :tick)
    {:ok, %{fire: Fire.new(80, 8), canvas: Canvas.new(80, 8)}}
  end

  def handle_info(:tick, %{fire: fire, canvas: canvas} = state) do
    canvas = Canvas.clear(canvas)
    canvas = Fire.draw(fire, canvas)
    fire = Fire.step(fire)
    send_frame(canvas |> Canvas.to_frame())
    {:noreply, %{state | fire: fire, canvas: canvas}}
  end
end
