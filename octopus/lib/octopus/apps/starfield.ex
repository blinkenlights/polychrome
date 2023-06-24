defmodule Octopus.Apps.Starfield do
  @moduledoc """
  This app draws a randomly scrolling starfield with a parallax effect.
  """

  use Octopus.App

  alias Octopus.Canvas

  defstruct [:width, :height, :stars, :canvas, :config]

  @frame_rate 60
  @frame_time_s 1 / @frame_rate
  @frame_time_ms trunc(1000 / @frame_rate)

  def name, do: "Starfield"

  def config_schema() do
    %{
      speed: {"Speed", :float, %{min: 0.01, max: 10.0, default: 1.0}},
      rotation: {"Rotation", :float, %{min: 0.0, max: 360.0, default: 90.0}}
    }
  end

  def get_config(state) do
    %{
      speed: state.config.speed,
      rotation: state.config.rotation
    }
  end

  def init(_) do
    width = (8 * 10 + 9 * 16) * 2
    height = 8 * 2

    config = config_schema() |> default_config()

    state = %__MODULE__{
      stars: %{},
      width: width,
      height: height,
      canvas: Canvas.new(8 * 10 + 9 * 18, 8, "pico-8"),
      config: config
    }

    state = state |> generate_stars(512)

    :timer.send_interval(@frame_time_ms, :tick)

    {:ok, state}
  end

  def handle_config(config, state) do
    config = Map.merge(state.config, config)
    {:reply, config, %__MODULE__{state | config: config}}
  end

  def handle_info(:tick, state) do
    state =
      state
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

  defp update_stars(%__MODULE__{stars: stars} = state) do
    stars =
      stars
      |> Enum.map(fn {{x, y}, speed} ->
        dx = :math.cos(state.config.rotation * :math.pi() / 180.0)
        dy = :math.sin(state.config.rotation * :math.pi() / 180.0)
        x = fmod(x + dx * speed * state.config.speed * @frame_time_s, state.width)
        y = fmod(y + dy * speed * state.config.speed * @frame_time_s, state.height)
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

        canvas |> Canvas.put_pixel({x, y}, color)
      end)

    %__MODULE__{state | canvas: canvas}
  end

  defp broadcast_frame(%__MODULE__{canvas: canvas} = state) do
    canvas |> Canvas.to_frame(drop: true) |> send_frame()
    state
  end

  defp fmod(dividend, divisor) do
    quotient = floor(dividend / divisor)
    dividend - quotient * divisor
  end
end
