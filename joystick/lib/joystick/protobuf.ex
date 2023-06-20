defmodule Joystick.Protobuf do
  require Logger

  alias Joystick.Protobuf.{InputEvent, Packet}

  def encode(%InputEvent{} = input_event) do
    %Packet{content: {:input_event, input_event}}
    |> Packet.encode()
  end
end
