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
      apps: [
        Octopus.Apps.PixelFun,
        Octopus.Apps.MarioRun,
        Octopus.Apps.Sprites,
        Octopus.Apps.Webpanimation
      ],
      index: -1,
      running_since: nil
    }

    # subscribe()
    Process.send_after(self(), :tick, 0)
    {:ok, state}
  end

  def handle_info(:tick, %State{} = state) do
    if state.index >= 0 do
      state.apps
      |> Enum.at(state.index)
      |> app_id_of_running_app()
      |> AppSupervisor.stop_app()
    end

    Process.send_after(self(), :tick, @max_running_time)
    state = start_next_app(state)
    {:noreply, state}
  end

  def handle_info({:apps, {:stopped, _app_id, _module}}, state) do
    state = start_next_app(state)
    {:noreply, state}
  end

  defp start_next_app(state) do
    new_index = rem(state.index + 1, Enum.count(state.apps))

    new_app = Enum.at(state.apps, new_index)
    AppSupervisor.start_app(new_app)

    new_app
    |> app_id_of_running_app()
    |> Octopus.Mixer.select_app()

    %State{state | index: new_index, running_since: Time.utc_now()}
  end

  defp subscribe() do
    Phoenix.PubSub.subscribe(Octopus.PubSub, "apps")
  end

  defp app_id_of_running_app(app_module_to_look_for) do
    running_apps = AppSupervisor.running_apps()

    {_, id} =
      Enum.find(running_apps, fn {app_module, _app_id} -> app_module == app_module_to_look_for end)

    id
  end
end
