defmodule Octopus.AppSupervisor do
  use DynamicSupervisor
  require Logger

  alias Octopus.Mixer
  alias Octopus.Protobuf.{InputEvent}

  @moduledoc """
  The AppRegistry is a DynamicSupervisor that keeps track of all running apps.

  Each app gets a unique app_id that is used in the mixer to select the frames.
  """

  def start_link(_) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc """
  Subscribes to the apps topic.

  Published messages:
  * `{:apps, {:started, app_id, module}}` - an app was started
  * `{:apps, {:stopped, app_id}}` - an app was stopped
  """
  def subscribe() do
    Phoenix.PubSub.subscribe(Octopus.PubSub, "apps")
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
    app_id = generate_app_id()
    name = {:via, Registry, {Octopus.AppRegistry, app_id}}

    # select app in mixer if there is no other app running
    if running_apps() == [] do
      Mixer.select_app(app_id)
    end

    {:ok, pid} = DynamicSupervisor.start_child(__MODULE__, {module, name: name})
    Phoenix.PubSub.broadcast(Octopus.PubSub, "apps", {:apps, {:started, app_id, module}})

    {:ok, pid}
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
    Phoenix.PubSub.broadcast(Octopus.PubSub, "apps", {:apps, {:stopped, app_id}})

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

  @doc """
  Sends an input_event to an app. Ignores the event if the app is not running.
  """
  def send_input(app_id, %InputEvent{} = input_event) do
    case Registry.lookup(Octopus.AppRegistry, app_id) do
      [{pid, _}] -> send(pid, {:input, input_event})
      [] -> :noop
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
