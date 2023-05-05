defmodule Octopus.Selector do
  use GenServer
  require Logger

  alias Octopus.Protobuf.{Config, Frame}
  alias Octopus.ColorPalettes

  defstruct []

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    state = %__MODULE__{}

    {:ok, state}
  end

  # TODO
end
