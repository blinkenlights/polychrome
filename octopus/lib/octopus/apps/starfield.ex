defmodule Octopus.Apps.Starfield do
  @moduledoc """
  This app draws a randomly scrolling starfield with a parallax effect.
  """

  use Octopus.App

  alias Octopus.Canvas

  defstruct [:width, :height, :stars, :velocity, :canvas]

  @frame_rate 60
  @frame_time_ms trunc(1000 / @frame_rate)

  def name, do: "Starfield"

  def init(_) do
    width = (8 * 10 + 9 * 18) * 2
    height = 8 * 2

    state = %__MODULE__{
      stars: %{},
      width: width,
      height: height,
      velocity: {0.05, 0.07},
      canvas: Canvas.new(8 * 10 + 9 * 18, 8, "pico-8")
    }

    state = state |> generate_stars(512)

    :timer.send_interval(@frame_time_ms, :tick)

    {:ok, state}
  end

  def handle_info(:tick, state) do
    state =
      state
      |> update_velocity()
      |> update_stars()
      |> update_canvas()
      |> broadcast_frame()

    {:noreply, state}
  end

  defp generate_stars(%__MODULE__{stars: stars} = state, count) do
    stars =
      Enum.reduce(0..count, stars, fn _i, stars ->
        x = :rand.uniform(state.width) - 1
        y = :rand.uniform(state.height) - 1
        speed = 1 + :rand.uniform() * 3
        Map.put(stars, {x, y}, speed)
      end)

    %__MODULE__{state | stars: stars}
  end

  defp update_velocity(%__MODULE__{velocity: {vx, vy}} = state) do
    vx = vx + :rand.uniform() * 0.02 - 0.01
    vy = vy + :rand.uniform() * 0.02 - 0.01
    vx = min(0.05, max(-0.05, vx))
    vy = min(0.05, max(-0.05, vy))

    %__MODULE__{state | velocity: {vx, vy}}
  end

  defp update_stars(%__MODULE__{stars: stars, velocity: {vx, vy}} = state) do
    stars =
      stars
      |> Enum.map(fn {{x, y}, speed} ->
        x = fmod(x + vx * speed, state.width)
        y = fmod(y + vy * speed, state.height)
        {{x, y}, speed}
      end)
      |> Map.new()

    %__MODULE__{state | stars: stars}
  end

  defp update_canvas(%__MODULE__{canvas: canvas, stars: stars} = state) do
    canvas = canvas |> Canvas.clear()

    canvas =
      stars
      |> Enum.sort_by(fn {_, speed} -> speed end)
      |> Enum.reduce(canvas, fn {{x, y}, speed}, canvas ->
        x = trunc(x)
        y = trunc(y)

        color =
          cond do
            speed < 2 -> 1
            speed < 3 -> 5
            true -> 7
          end

        canvas |> Canvas.put_pixel(x, y, color)
      end)

    %__MODULE__{state | canvas: canvas}
  end

  defp broadcast_frame(%__MODULE__{canvas: canvas} = state) do
    canvas |> Canvas.to_frame() |> send_frame()
    state
  end

  defp fmod(dividend, divisor) do
    quotient = floor(dividend / divisor)
    dividend - quotient * divisor
  end
end
