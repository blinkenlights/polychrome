defmodule Octopus.Apps.RoundRobinScheduler do
  use Octopus.App
  require Logger

  alias Octopus.AppSupervisor

  defmodule State do
    defstruct [:apps, :index, :running_since]
  end

  @max_running_time 600_000

  def name(), do: "RoundRobinScheduler"

  def init(_args) do
    state = %State{
      apps: [Octopus.Apps.PixelFun, Octopus.Apps.MarioRun, Octopus.Apps.Webpanimation],
      index: -1,
      running_since: nil
    }

    Process.send_after(self(), :tick, 0)
    {:ok, state}
  end

  def handle_info(:tick, %State{} = state) do
    Process.send_after(self(), :tick, @max_running_time)
    state = start_next_app(state)
    {:noreply, state}
  end

  defp start_next_app(state) do
    if state.index >= 0 do
      AppSupervisor.stop_app(Enum.at(state.apps, state.index))
    end

    new_index = rem(state.index + 1, Enum.count(state.apps))

    new_app = Enum.at(state.apps, new_index)
    AppSupervisor.start_app(new_app)

    running_apps = AppSupervisor.running_apps()
    Logger.info("Running apps: #{inspect(running_apps)}")

    {_, id} = Enum.find(running_apps, fn {app_module, app_id} -> app_module == new_app end)
    Octopus.Mixer.select_app(id)
    %State{state | index: new_index, running_since: Time.utc_now()}
  end
end
