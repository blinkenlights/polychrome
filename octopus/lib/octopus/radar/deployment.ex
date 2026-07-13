defmodule Octopus.Radar.Deployment do
  @moduledoc false
  # Resolves deployment port bindings and adapter metadata.
  #
  # Each deployment entry declares a `:target` (`:linux` or `:macos`). The
  # active entry is selected from config by `host_target/0`. Linux-target
  # deployments discover `/dev/serial/by-id/...` paths and sysfs `usb_path`
  # values at runtime; macOS-target deployments use explicit `:ports` only.

  require Logger

  alias Octopus.Radar.{LogFormat, SensorPlan}

  @by_id_prefix "/dev/serial/by-id/usb-WCH.CN_USB_Quad_Serial_"
  @interface_suffix ~r/-if(\d+)$/

  @type port_ref :: {String.t(), atom()}
  @type port_registry :: %{port_ref() => String.t()}
  @type target :: :linux | :macos

  @doc """
  Map the runtime OS to the deployment `:target` key used in `config/radar.exs`.
  """
  @spec host_target() :: target() | nil
  def host_target do
    case :os.type() do
      {:unix, :linux} -> :linux
      {:unix, :darwin} -> :macos
      _ -> nil
    end
  end

  @doc """
  Fill in adapter `:ports` from live hardware when `:serial` is configured.

  Serial discovery runs for `:target :linux` only. Explicit `:ports` are kept
  as a fallback when discovery finds nothing or the target is `:macos`.
  """
  @spec enrich(keyword() | nil) :: keyword() | nil
  def enrich(nil), do: nil

  def enrich(deployment) do
    adapters =
      deployment
      |> Keyword.get(:adapters, [])
      |> Enum.map(&enrich_adapter(&1, deployment))

    Keyword.put(deployment, :adapters, adapters)
  end

  @doc """
  Build a lookup from `{adapter_name, port_name}` to the serial device path.
  """
  @spec port_registry(keyword() | nil) :: port_registry()
  def port_registry(nil), do: %{}

  def port_registry(deployment) do
    deployment
    |> enrich()
    |> Keyword.get(:adapters, [])
    |> Enum.reduce(%{}, fn adapter_opts, acc ->
      name = Keyword.fetch!(adapter_opts, :name)

      adapter_opts
      |> Keyword.fetch!(:ports)
      |> Enum.reduce(acc, fn {port_name, path}, acc2 ->
        Map.put(acc2, {name, port_name}, path)
      end)
    end)
  end

  @doc """
  Resolve a sensor binding to a serial port path.

  Supports:

    * direct path — `[id: :a, port: "/dev/ttyUSB0"]`
    * adapter reference — `[id: :a, adapter: "65", port: :if00]`
  """
  @spec resolve_port(keyword(), port_registry()) :: {:ok, String.t()} | {:error, term()}
  def resolve_port(binding, registry) do
    adapter = Keyword.get(binding, :adapter)
    port_name = Keyword.get(binding, :port)
    direct = Keyword.get(binding, :port)

    cond do
      is_binary(direct) and direct != "" and is_nil(adapter) ->
        {:ok, direct}

      not is_nil(adapter) and not is_nil(port_name) ->
        case Map.fetch(registry, {adapter, port_name}) do
          {:ok, path} -> {:ok, path}
          :error -> {:error, {:unknown_port, adapter, port_name}}
        end

      true ->
        {:error, :missing_port}
    end
  end

  @doc """
  Return USB adapter metadata with the logical `device_id`s bound to each adapter.

  For `:target :linux`, `usb_path` is resolved from sysfs at call time. For
  `:target :macos`, the static `:usb_path` from config is used when present.
  """
  @spec adapters(keyword() | nil, keyword() | nil) :: [
          %{name: String.t(), usb_path: String.t() | nil, device_ids: [pos_integer()]}
        ]
  def adapters(nil, _installation_radar), do: []
  def adapters(_deployment, nil), do: []

  def adapters(deployment, installation_radar) do
    deployment = enrich(deployment)
    adapter_defs = Keyword.get(deployment, :adapters, [])

    if adapter_defs == [] do
      []
    else
      device_by_sensor =
        installation_radar
        |> SensorPlan.build(deployment, :live)
        |> Map.new(fn {device_id, cfg} -> {cfg[:sensor_id], device_id} end)

      deployment
      |> Keyword.get(:sensors, [])
      |> Enum.filter(&(Keyword.get(&1, :adapter) != nil))
      |> Enum.group_by(&Keyword.fetch!(&1, :adapter))
      |> Enum.map(fn {adapter_name, sensor_bindings} ->
        adapter_def =
          Enum.find(adapter_defs, fn opts ->
            Keyword.fetch!(opts, :name) == adapter_name
          end)

        device_ids =
          sensor_bindings
          |> Enum.map(fn binding ->
            Map.fetch!(device_by_sensor, Keyword.fetch!(binding, :id))
          end)
          |> Enum.sort()

        %{
          name: adapter_name,
          usb_path: resolve_usb_path(adapter_def, deployment),
          device_ids: device_ids
        }
      end)
      |> Enum.sort_by(& &1.name)
    end
  end

  @doc """
  Discover `/dev/serial/by-id/...` paths for a WCH quad-serial adapter serial.

  Returns a keyword list like `[if00: "/dev/serial/...", if02: "..."]`.
  Returns `[]` unless `deployment` has `:target :linux`.
  """
  @spec discover_ports_for_serial(String.t()) :: keyword()
  @spec discover_ports_for_serial(String.t(), keyword()) :: keyword()
  def discover_ports_for_serial(serial) when is_binary(serial),
    do: discover_ports_for_serial(serial, [])

  def discover_ports_for_serial(serial, deployment) when is_binary(serial) do
    if linux_usb?(deployment) do
      "#{@by_id_prefix}#{serial}-if*"
      |> Path.wildcard()
      |> Enum.sort()
      |> Enum.flat_map(&port_entry_from_by_id/1)
    else
      []
    end
  end

  @doc """
  Resolve the sysfs USB device segment (e.g. `"1-1.4"`) for a by-id serial port.

  Used for USB power-cycling via `/sys/bus/usb/devices/<path>/authorized`.
  Returns `{:error, :unsupported_target}` unless `deployment` has `:target :linux`.
  """
  @spec usb_path_for_port(String.t()) :: {:ok, String.t()} | {:error, term()}
  @spec usb_path_for_port(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def usb_path_for_port(by_id_path) when is_binary(by_id_path),
    do: usb_path_for_port(by_id_path, [])

  def usb_path_for_port(by_id_path, deployment) when is_binary(by_id_path) do
    if linux_usb?(deployment) do
      resolve_usb_path_for_port(by_id_path)
    else
      {:error, :unsupported_target}
    end
  end

  defp resolve_usb_path_for_port(by_id_path) do
    with {:ok, tty_path} <- by_id_to_tty(by_id_path),
         tty_name when is_binary(tty_name) <- Path.basename(tty_path),
         device_link = Path.join(["/sys/class/tty", tty_name, "device"]),
         {:ok, _} <- File.read_link(device_link) do
      usb_path =
        device_link
        |> Path.expand()
        |> Path.dirname()
        |> Path.basename()

      {:ok, usb_path}
    else
      {:error, _} = err -> err
      _ -> {:error, :missing_sysfs}
    end
  end

  defp enrich_adapter(adapter_opts, deployment) do
    ports = resolve_adapter_ports(adapter_opts, deployment)
    adapter_opts = Keyword.put(adapter_opts, :ports, ports)

    case Keyword.get(adapter_opts, :serial) do
      serial when is_binary(serial) and ports != [] ->
        usb_path =
          ports
          |> Keyword.values()
          |> Enum.find_value(fn path ->
            if by_id_path?(path) do
              case usb_path_for_port(path, deployment) do
                {:ok, usb} -> usb
                _ -> nil
              end
            end
          end)

        log_discovered_adapter(adapter_opts, serial, ports, usb_path)
        adapter_opts

      _ ->
        adapter_opts
    end
  end

  defp by_id_path?(path), do: String.starts_with?(path, @by_id_prefix)

  defp resolve_adapter_ports(adapter_opts, deployment) do
    discovered =
      if linux_usb?(deployment) do
        case Keyword.get(adapter_opts, :serial) do
          serial when is_binary(serial) -> discover_ports_for_serial(serial, deployment)
          _ -> []
        end
      else
        []
      end

    case discovered do
      [] -> Keyword.get(adapter_opts, :ports, [])
      ports -> ports
    end
  end

  defp resolve_usb_path(adapter_def, deployment) do
    discovered =
      if linux_usb?(deployment) do
        adapter_def
        |> Keyword.get(:ports, [])
        |> Enum.find_value(fn {_port_name, path} ->
          if is_binary(path) and by_id_path?(path) do
            case usb_path_for_port(path, deployment) do
              {:ok, usb_path} -> usb_path
              _ -> nil
            end
          end
        end)
      end

    discovered || Keyword.get(adapter_def, :usb_path)
  end

  defp linux_usb?(deployment), do: Keyword.get(deployment, :target) == :linux

  defp port_entry_from_by_id(path) do
    case Regex.run(@interface_suffix, path) do
      [_, suffix] -> [{String.to_atom("if#{suffix}"), path}]
      _ -> []
    end
  end

  defp by_id_to_tty(by_id_path) do
    case File.read_link(by_id_path) do
      {:ok, rel} -> {:ok, Path.expand(rel, Path.dirname(by_id_path))}
      {:error, _} = err -> err
    end
  end

  defp log_discovered_adapter(adapter_opts, serial, ports, usb_path) do
    name = Keyword.fetch!(adapter_opts, :name)

    port_labels =
      ports
      |> Enum.map(fn {port_name, path} -> "#{port_name}=#{LogFormat.short_port(path)}" end)
      |> Enum.join(", ")

    Logger.info(
      "[radar] adapter #{name} serial #{serial} usb_path=#{usb_path || "?"} ports: #{port_labels}"
    )
  end
end
