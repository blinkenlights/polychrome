defmodule Octopus.Params.Global do
  use Octopus.Params, prefix: :global

  def brightness, do: param(:brightness, 255)

  def handle_param("brightness", value) do
    Octopus.Broadcaster.set_luminance(value |> min(255) |> max(0))
  end
end
