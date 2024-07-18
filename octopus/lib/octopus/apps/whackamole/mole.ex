defmodule Octopus.Apps.Whackamole.Mole do
  defstruct [:pannel, :start_tick]

  def new(pannel, start_tick) do
    %__MODULE__{
      pannel: pannel,
      start_tick: start_tick
    }
  end
end
