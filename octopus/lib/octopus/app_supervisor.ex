defmodule Octopus.AppSupervisor do
  use DynamicSupervisor
  require Logger

  alias Octopus.{AppManager, App, Mixer}
  alias Octopus.Events.Event.Audio, as: AudioEvent
  alias Octopus.Events.Event.Proximity, as: ProximityEvent
  alias Octopus.Events.Event.Input, as: InputEvent
  alias Octopus.Events.Event.Lifecycle, as: LifecycleEvent

  @topic "apps"

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
    Phoenix.PubSub.subscribe(Octopus.PubSub, @topic)
  end

  @doc """
  Lists all avaiable apps. An app is available if it uses the `Octopus.App` behaviour.
  """
  def available_apps() do
    {:ok, modules} = :application.get_key(:octopus, :modules)

    Enum.filter(modules, fn module ->
      try do
        Octopus.App in (module.__info__(:attributes)[:behaviour] || [])
      rescue
        _ -> false
      end
    end)
  end

  @doc """
  Starts an app in the Front App slot. Stops the current front app (if different from the
  current mask app) and selects the new app as front.
  """
  def start_as_front_app(module, opts \\ []) when is_atom(module) do
    with {:ok, config} <- validate_and_build_config(module, opts) do
      old_front = AppManager.get_selected_app()
      old_mask = AppManager.get_mask_app()

      case do_start_raw(module, config) do
        {:ok, new_id} ->
          AppManager.select_app(new_id)
          # Only stop single-app fronts; dual-side fronts (tuples) are managed externally
          if is_binary(old_front) do
            stop_slot_app(old_front, preserve: [old_mask, new_id])
          end
          {:ok, new_id}

        err ->
          err
      end
    end
  end

  @doc """
  Starts an app in the Mask App slot. Only greyscale-capable apps are allowed.
  Stops the current mask app (if different from the current front app) and sets the
  new app as mask.
  """
  def start_as_mask_app(module, opts \\ []) when is_atom(module) do
    cond do
      module not in available_apps() ->
        Logger.error("App #{module} not found")
        {:error, :app_not_found}

      not apply(module, :compatible?, []) ->
        Logger.info("App #{module} is not compatible with current installation")
        {:error, :incompatible}

      apply(module, :output_type, []) not in [:grayscale, :both] ->
        Logger.info("App #{module} does not support greyscale output — cannot be used as mask")
        {:error, :not_grayscale}

      true ->
        default_config = module |> App.config_schema() |> App.default_config()
        config = Keyword.get(opts, :config, %{})
        config = default_config |> Map.merge(config) |> Map.put_new(:bleeding, 0.0)

        old_mask = AppManager.get_mask_app()
        old_front = AppManager.get_selected_app()

        # Tell the Mixer to use the front app's layout for the mask app's display buffers,
        # so both apps share the same coordinate system.
        front_layout = front_app_layout(old_front)
        Mixer.set_pending_mask_layout(front_layout)

        case do_start_raw(module, config) do
          {:ok, new_id} ->
            AppManager.set_mask_app(new_id)
            stop_slot_app(old_mask, preserve: [old_front, new_id])
            {:ok, new_id}

          err ->
            Mixer.set_pending_mask_layout(nil)
            err
        end
    end
  end

  @doc """
  Stops the app currently occupying the Front App slot.
  """
  def stop_front_app() do
    case AppManager.get_selected_app() do
      nil -> :ok
      app_id -> stop_app(app_id)
    end
  end

  @doc """
  Stops the app currently occupying the Mask App slot.
  """
  def stop_mask_app() do
    case AppManager.get_mask_app() do
      nil -> :ok
      app_id -> stop_app(app_id)
    end
  end

  @doc """
  Starts an app in the Front App slot. Alias for `start_as_front_app/2`.
  """
  def start_app(module, opts \\ []) when is_atom(module) do
    start_as_front_app(module, opts)
  end

  @doc """
  Starts an app in the Front App slot if not already running, otherwise selects the
  existing instance. Alias for `start_or_select_as_front_app/2`.
  """
  def start_or_select_app(module, opts \\ []) when is_atom(module) do
    case find_running_app(module) do
      {:ok, existing_app_id} ->
        Logger.info("App #{module} already running with id #{existing_app_id}, selecting it")
        {:ok, existing_app_id}

      :not_found ->
        start_as_front_app(module, opts)
    end
  end

  @doc """
  Finds a running app by module. Returns {:ok, app_id} if found, :not_found otherwise.
  """
  def find_running_app(module) when is_atom(module) do
    case Enum.find(running_apps(), fn {mod, _app_id} -> mod == module end) do
      {^module, app_id} -> {:ok, app_id}
      nil -> :not_found
    end
  end

  defp validate_and_build_config(module, opts) do
    cond do
      module not in available_apps() ->
        Logger.error("App #{module} not found")
        {:error, :app_not_found}

      not apply(module, :compatible?, []) ->
        Logger.info("App #{module} is not compatible with current installation")
        {:error, :incompatible}

      true ->
        default_config = module |> App.config_schema() |> App.default_config()
        config = Keyword.get(opts, :config, %{})
        config = default_config |> Map.merge(config) |> Map.put_new(:bleeding, 0.0)
        {:ok, config}
    end
  end

  defp do_start_raw(module, config) when is_atom(module) do
    app_id = generate_app_id()
    name = {:via, Registry, {Octopus.AppRegistry, app_id, module}}

    case DynamicSupervisor.start_child(__MODULE__, {module, {config, name: name}}) do
      {:ok, _pid} ->
        Phoenix.PubSub.broadcast(Octopus.PubSub, @topic, {:apps, {:started, app_id, module}})
        {:ok, app_id}

      {:error, error} ->
        Logger.error("Could not start app #{module}: #{inspect(error)}")
        {:error, :start_failed}
    end
  end

  defp front_app_layout(nil), do: :gapped_panels

  defp front_app_layout(app_id) when is_binary(app_id) do
    case Mixer.get_app_display_info(app_id) do
      %{layout: layout} -> layout
      _ -> :gapped_panels
    end
  end

  defp front_app_layout(_), do: :gapped_panels

  defp stop_slot_app(nil, _opts), do: :ok

  defp stop_slot_app(app_id, opts) do
    preserve = Keyword.get(opts, :preserve, [])

    unless app_id in preserve do
      stop_app(app_id)
    end
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
  def stop_app(app_id) do
    if app_id == AppManager.get_selected_app() do
      GenServer.cast(Octopus.Mixer, :stop_audio_playback)
    end

    Phoenix.PubSub.broadcast(Octopus.PubSub, @topic, {:apps, {:stopped, app_id}})

    case Registry.lookup(Octopus.AppRegistry, app_id) do
      [{pid, _}] ->
        DynamicSupervisor.terminate_child(__MODULE__, pid)

      [] ->
        Logger.warning("App #{app_id} not found")
        :ok
    end
  end

  def update_config(app_id, config) when is_binary(app_id) do
    case Registry.lookup(Octopus.AppRegistry, app_id) do
      [{pid, _}] ->
        :ok = GenServer.call(pid, {:update_config, config})
        config = GenServer.call(pid, :get_config)

        Phoenix.PubSub.broadcast(
          Octopus.PubSub,
          @topic,
          {:apps, {:config_updated, app_id, config}}
        )

      [] ->
        Logger.warning("App #{app_id} not found")
        :ok
    end
  end

  def config(app_id) when is_binary(app_id) do
    case Registry.lookup(Octopus.AppRegistry, app_id) do
      [{pid, _}] ->
        GenServer.call(pid, :get_config)

      [] ->
        Logger.warning("App #{app_id} not found")
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
  Looks up the pid and module for a given app_id.
  """
  @spec lookup_app(binary(), term()) :: {pid(), atom()}
  def lookup_app(app_id, default \\ nil) do
    case Registry.lookup(Octopus.AppRegistry, app_id) do
      [{pid, module}] -> {pid, module}
      [] -> default
    end
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
  Sends an event to an app. Ignores the event if the app is not running.
  """
  def send_event(app_id, %event_type{} = event)
      when event_type in [InputEvent, LifecycleEvent, AudioEvent, ProximityEvent] do
    case Registry.lookup(Octopus.AppRegistry, app_id) do
      [{pid, _}] -> send(pid, {:event, event})
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
