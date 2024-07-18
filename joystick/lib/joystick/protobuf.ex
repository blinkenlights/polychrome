defmodule Joystick.Protobuf do
  require Logger

  alias Joystick.Protobuf.{InputLightEvent, InputEvent, Packet}

  def encode(%InputEvent{} = input_event) do
    %Packet{content: {:input_event, input_event}}
    |> Packet.encode()
  end

  def decode(protobuf) when is_binary(protobuf) do
    case Packet.decode(protobuf) do
      %Packet{content: {:input_light_event, %InputLightEvent{} = input_light_event}} ->
        {:ok, input_light_event}

      _ ->
        {:error, :unexpected_content}
    end
  rescue
    error ->
      Logger.warning("Could not decode protobuf: #{inspect(error)} Binary: #{inspect(protobuf)} ")
      {:error, :decode_error}
  end
end
