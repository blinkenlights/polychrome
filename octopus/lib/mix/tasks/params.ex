defmodule Mix.Tasks.Params do
  use Mix.Task

  @shortdoc "Prints all available params configureable via OSC"

  @impl true
  def run(_args) do
    Octopus.Params.all()
    |> Enum.each(fn {{prefix, key}, value} ->
      IO.puts("/#{prefix}/#{key}: #{value}")
    end)
  end
end
