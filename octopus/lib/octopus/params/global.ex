defmodule Octopus.Params.Global do
  use Octopus.Params, prefix: :global

  def brightness, do: param(:brightness, 128)
  def speed, do: param(:speed, 1.0)

  def handle_param("brightness", [value]) when is_number(value) do
    clamped_value = value |> min(255) |> max(0)
    Octopus.Broadcaster.set_luminance(clamped_value)
  end

  def handle_param("speed", [value]) when is_number(value) do
    _clamped_value = value |> min(10.0) |> max(0.1)
    # Speed parameter stored - could be used by animations for time scaling
    # Value is automatically stored in params system via put_param_and_reply
    :ok
  end

  def handle_param(_key, _value) do
    # ignore
  end
end
