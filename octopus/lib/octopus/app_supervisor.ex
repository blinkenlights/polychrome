defmodule Octopus.AppSupervisor do
  use DynamicSupervisor

  require Logger

  @moduledoc """
  The AppRegistry is a DynamicSupervisor that keeps track of all running apps.

  Each app gets a unique app_id that is used in the mixer to select the frames.
  """

  def start_link(_) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc """
  Lists all avaiable apps. An app is available if it uses the `Octopus.App` behaviour.
  """
  def available_apps() do
    {:ok, modules} = :application.get_key(:octopus, :modules)

    Enum.filter(modules, fn module ->
      Octopus.App in (module.module_info(:attributes)[:behaviour] || [])
    end)
  end

  @doc """
  Starts an app and assigns a unique app_id. It is possible to start multiple instances of the same app.
  """
  def start_app(module) when is_atom(module) do
    name = {:via, Registry, {Octopus.AppRegistry, generate_app_id()}}
    DynamicSupervisor.start_child(__MODULE__, {Octopus.Apps.SampleApp, name: name})
  end

  @doc """
  List all running apps with their app_id.
  """
  def running_apps() do
    DynamicSupervisor.which_children(__MODULE__)
    |> Enum.map(fn {_, pid, _, [module]} ->
      [app_id] = Registry.keys(Octopus.AppRegistry, pid)
      {module, app_id}
    end)
  end

  @doc """
  Stops an specific instance of an app.
  """
  def stop_app(app_id) when is_binary(app_id) do
    case Registry.lookup(Octopus.AppRegistry, app_id) do
      [{pid, _}] ->
        DynamicSupervisor.terminate_child(__MODULE__, pid)

      [] ->
        Logger.warn("App #{app_id} not found")
        :ok
    end
  end

  @doc """
  Stops all running apps.
  """
  def stop_all_apps() do
    running_apps()
    |> Enum.map(fn {_, app_id} -> stop_app(app_id) end)
  end

  @doc """
  Looks up the app_id for a given pid.
  """
  def lookup_app_id(pid) do
    case Registry.keys(Octopus.AppRegistry, pid) do
      [app_id] -> app_id
      [] -> raise "Process has no app_id"
    end
  end

  @impl true
  def init(:ok) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  defp generate_app_id() do
    alphabet = Enum.to_list(?a..?z) ++ Enum.to_list(?0..?9)
    Enum.map(1..6, fn _ -> Enum.random(alphabet) end) |> to_string()
  end
end
