defmodule Octopus.WebP do
  use Rustler,
    otp_app: :octopus,
    crate: :octopus_webp

  defstruct frames: [], size: nil

  def decode_animation(_path), do: :erlang.nif_error(:nif_not_loaded)

  def encode_rgb(_rgb_pixels, _width, _height), do: :erlang.nif_error(:nif_not_loaded)

  def decode_rgb(_path), do: :erlang.nif_error(:nif_not_loaded)
end
