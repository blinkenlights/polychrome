defmodule Octopus.WebP do
  use Rustler,
    otp_app: :octopus,
    crate: :octopus_webp

  defstruct frames: [], size: nil

  def decode(_path), do: :erlang.nif_error(:nif_not_loaded)
end
