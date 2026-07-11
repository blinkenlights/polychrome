defmodule Octopus.Sway do
  @moduledoc """
  Shared sinusoidal y-displacement for ring/circular displays.

  `y' = y + amplitude * sin(x * tau / w - phase)`

  Modes:
  - `:wobble` — constant amplitude, phase advances with time
  - `:pendulum` — amplitude oscillates, fixed phase axis

  TODO: A global sway clock could live in `Octopus.Params.Global` for cross-app sync.
  """

  @tau :math.pi() * 2

  @spec normalize_mode(atom() | String.t()) :: :wobble | :pendulum
  def normalize_mode(:wobble), do: :wobble
  def normalize_mode(:pendulum), do: :pendulum
  def normalize_mode("wobble"), do: :wobble
  def normalize_mode("pendulum"), do: :pendulum
  def normalize_mode(_), do: :wobble

  @spec params(number(), number(), atom() | String.t(), number()) :: {float(), float()}
  def params(scale, speed, mode, seconds) do
    case normalize_mode(mode) do
      :pendulum -> {scale * :math.sin(seconds * speed), 0.0}
      _ -> {scale, seconds * speed}
    end
  end

  @spec offset(number(), number(), number(), number()) :: float()
  def offset(x, w, amplitude, phase) when w > 0 do
    amplitude * :math.sin(x * @tau / w - phase)
  end
end
