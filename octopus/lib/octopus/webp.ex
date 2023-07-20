defmodule Octopus.WebP do
  use Rustler,
    otp_app: :octopus,
    crate: :octopus_webp

  defstruct frames: []

  def decode(_path), do: :erlang.nif_error(:nif_not_loaded)
end

# type Frame = (Vec<Vec<u8>>, i32);

# #[derive(Default, NifStruct)]
# #[module = "Octopus.WebP"]
# struct Animation {
#     frames: Vec<Frame>,
# }
