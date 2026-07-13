defmodule Octopus.Radar do
  @moduledoc """
  Public facade and supervisor for the HLK-LD6001A-60G radar layer.

  This module both supervises one `Octopus.Radar.Sensor` per configured
  device and exposes the consumer-facing API for subscribing to tracking
  data.

  ## Configuration

  Radar is split between **installation** (logical layout) and **deployment**
  (physical hardware on a specific host).

  ### Installation (`:radar` in the installation module)

  The active installation defines how many sensors exist, their logical ids,
  and how they are arranged (e.g. radial layout, distance). In a radial layout
  each sensor's local +X points outward automatically, so `rotation_deg` is
  only needed as a small per-sensor correction (default `0`):

      radar: [
        defaults: [sensitivity: :normal, height_cm: 500, range_cm: 500, ...],
        layout: [
          type: :radial,
          sensors: [:a, :b, :c, :d, :e, :f],
          start_angle_deg: 120,
          distance_cm: 300
        ]
      ]

  See `Octopus.Installation.Nation2026` for a full example.

  ### Deployment (`config/radar.exs`)

  Each host that has real sensors has an entry in the `deployments` map in
  `config/radar.exs`, keyed by the machine's short hostname (selected
  automatically at boot — no environment variable). The entry maps logical
  sensor ids to serial ports and optional USB adapter metadata:

      "redlady" => [
        defaults: [type: :ld6001a, baud: 115_200],
        sensors: [
          [id: :a, port: "/dev/serial/by-id/..."],
          ...
        ],
        adapters: [...]
      ]

  On a host with no matching entry (e.g. local dev on a Mac), Live mode is
  unavailable but Mock mode still works using synthetic ports.

  ### Boot source mode (`config/radar.exs`)

  * `:boot_source_mode` — `:off`, `:live`, `:exact`, or `:fuzzy`; overridable via
    `RADAR_SOURCE_MODE` (defaults to `:off` in dev, `:live` in prod).

  Use `live_available?/0` to check whether this host can run Live mode.

  The integer **`device_id` is the 1-based position** in the installation's
  `:sensors` list and is used both to register the sensor process and as the
  tag in PubSub messages.

  ## PubSub

  Each parsed frame is broadcast on two topics:

    * `topic/0` — global, every sensor
    * `topic/1` — single sensor, identified by `device_id`

  In both cases the message envelope is:

      {:radar_frame, device_id :: pos_integer(), %Octopus.Radar.Frame{}}

  ## Consumer example

      defmodule MyConsumer do
        use GenServer

        def init(_) do
          Octopus.Radar.subscribe()
          {:ok, %{}}
        end

        def handle_info({:radar_frame, device_id, frame}, state) do
          IO.inspect({device_id, length(frame.tracks)})
          {:noreply, state}
        end
      end
  """

  use Supervisor
  require Logger

  alias Octopus.Radar.{
    LogFormat,
    Mock,
    PoseTweak,
    Runtime,
    Sensitivity,
    Sensor,
    SensorPlan,
    SensorType,
    SourceMode,
    ViewSettings
  }

  @topic "radar:hlk6001"

  ## Public API

  @doc "Global PubSub topic — fan-in of frames from all sensors."
  @spec topic() :: String.t()
  def topic, do: @topic

  @doc "Map 1-based device_id to UI letter (1 → A, 2 → B, …)."
  @spec device_letter(pos_integer()) :: String.t()
  defdelegate device_letter(device_id), to: LogFormat

  @doc false
  @spec short_port(String.t()) :: String.t()
  defdelegate short_port(path), to: LogFormat

  @doc "PubSub topic for a single sensor identified by `device_id`."
  @spec topic(pos_integer()) :: String.t()
  def topic(device_id) when is_integer(device_id) and device_id >= 1,
    do: "#{@topic}:#{device_id}"

  @doc "Subscribe to frames from all sensors."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: Phoenix.PubSub.subscribe(Octopus.PubSub, topic())

  @doc "Subscribe to frames from a single sensor."
  @spec subscribe(pos_integer()) :: :ok | {:error, term()}
  def subscribe(device_id), do: Phoenix.PubSub.subscribe(Octopus.PubSub, topic(device_id))

  @doc """
  Return a list of configured USB adapters, each with its display name,
  sysfs USB path, and the device_ids of the sensors it carries.

  Returns `[]` when no `:adapters` key is present in the config (i.e. when
  using the plain `:ports` style).
  """
  @spec adapters() :: [
          %{name: String.t(), usb_path: String.t(), device_ids: [pos_integer()]}
        ]
  def adapters do
    if not configured?() do
      []
    else
      deployment_config()
      |> case do
        nil -> []
        deployment -> Keyword.get(deployment, :adapters, [])
      end
      |> Enum.reduce({[], 1}, fn adapter_opts, {acc, id_start} ->
        ports = Keyword.fetch!(adapter_opts, :ports)
        count = length(ports)
        device_ids = Enum.to_list(id_start..(id_start + count - 1))

        entry = %{
          name: Keyword.fetch!(adapter_opts, :name),
          usb_path: Keyword.fetch!(adapter_opts, :usb_path),
          device_ids: device_ids
        }

        {acc ++ [entry], id_start + count}
      end)
      |> elem(0)
    end
  end

  @doc """
  Trigger a USB-level power cycle for the named adapter by toggling the
  kernel's `authorized` sysfs attribute.

  Broadcasts `:resetting` for all sensors on the adapter, waits 500 ms so
  the UI shows the black indicator, then deauthorizes the USB device for
  1 second before reauthorizing it.  The sensors recover automatically via
  the normal `try_open → :probing → :running` flow.

  Requires the container/process to have `SYS_ADMIN` capability and access
  to `/sys/bus/usb/devices/`.  Returns `{:error, :not_found}` if the adapter
  name is not configured, or `{:error, :no_adapters_configured}` when the
  config uses plain `:ports` rather than `:adapters`.
  """
  @spec reset_adapter(String.t()) :: :ok | {:error, atom()}
  def reset_adapter(adapter_name) do
    require Logger

    case Enum.find(adapters(), fn a -> a.name == adapter_name end) do
      nil ->
        {:error, :not_found}

      adapter ->
        Enum.each(adapter.device_ids, &broadcast_status(&1, :resetting))

        sysfs_base = "/sys/bus/usb/devices/#{adapter.usb_path}"

        Task.start(fn ->
          Process.sleep(500)

          case File.write("#{sysfs_base}/authorized", "0") do
            :ok ->
              Logger.info(
                "[radar] USB adapter #{adapter_name} (#{adapter.usb_path}) deauthorized — power cycling"
              )

              Process.sleep(1_000)

              case File.write("#{sysfs_base}/authorized", "1") do
                :ok ->
                  Logger.info(
                    "[radar] USB adapter #{adapter_name} (#{adapter.usb_path}) reauthorized"
                  )

                {:error, reason} ->
                  Logger.error(
                    "[radar] Failed to reauthorize USB adapter #{adapter_name}: #{inspect(reason)}"
                  )
              end

            {:error, reason} ->
              Logger.error(
                "[radar] Failed to deauthorize USB adapter #{adapter_name} at #{sysfs_base}: #{inspect(reason)}"
              )

              Enum.each(adapter.device_ids, &broadcast_status(&1, :unavailable))
          end
        end)

        :ok
    end
  end

  @doc """
  Return a list describing each configured sensor in `device_id` order.

  Includes sensors whose port does not currently exist; consult `:port`
  with `File.exists?/1` if the caller cares about presence.

  The reported `sensitivity_level` is on a 1..9 UI scale (1 = least
  sensitive, 9 = most). The device-native register value is internal.
  Installations configure presets (`:normal`, `:lower`, `:higher`) or an
  explicit device value; see `Octopus.Radar.SensorType`.
  """
  @spec devices() :: [
          %{
            device_id: pos_integer(),
            type: atom(),
            enabled: boolean(),
            port: String.t(),
            baud: pos_integer(),
            sensitivity_level: 1..9,
            angle_deg: number(),
            distance_cm: number(),
            rotation_deg: number(),
            x_pos_cm: integer(),
            x_neg_cm: integer(),
            y_pos_cm: integer(),
            y_neg_cm: integer(),
            range_cm: pos_integer(),
            height_cm: pos_integer()
          }
        ]
  def devices do
    sensor_configs()
    |> devices_from_configs()
  end

  @doc """
  Return planned sensor geometry from the installation layout, regardless of
  the current source mode. Used for static map overlays when sensors are off.
  """
  @spec planned_devices() :: [map()]
  def planned_devices do
    if configured?() do
      installation_radar = Octopus.Installation.radar_config()
      deployment = deployment_config()

      SensorPlan.build(installation_radar, deployment, :exact)
      |> devices_from_configs()
    else
      []
    end
  end

  @doc """
  Return `true` when a sensor is enabled in runtime under the current source mode.
  """
  @spec sensor_active?(pos_integer()) :: boolean()
  def sensor_active?(device_id) do
    Runtime.enabled?(device_id) and
      Enum.any?(sensor_configs(), fn {id, _} -> id == device_id end)
  end

  defp devices_from_configs(configs) do
    Enum.map(configs, &device_from_config/1)
  end

  defp device_from_config({device_id, config}) do
    type = Keyword.fetch!(config, :type)

    %{
      device_id: device_id,
      type: type,
      enabled: Keyword.fetch!(config, :enabled),
      port: Keyword.fetch!(config, :port),
      baud: Keyword.fetch!(config, :baud),
      sensitivity_level: sensitivity_level(),
      angle_deg: Keyword.fetch!(config, :angle_deg),
      distance_cm: Keyword.fetch!(config, :distance_cm),
      rotation_deg: Keyword.fetch!(config, :rotation_deg),
      x_pos_cm: Keyword.fetch!(config, :x_pos_cm),
      x_neg_cm: Keyword.fetch!(config, :x_neg_cm),
      y_pos_cm: Keyword.fetch!(config, :y_pos_cm),
      y_neg_cm: Keyword.fetch!(config, :y_neg_cm),
      range_cm: Keyword.fetch!(config, :range_cm),
      height_cm: Keyword.fetch!(config, :height_cm)
    }
  end

  @doc """
  Current UI sensitivity level shared across all sensors (1 = least, 9 = most).

  Reads the runtime tweak when present, otherwise the installation default.
  """
  @spec sensitivity_level() :: 1..9
  def sensitivity_level do
    if Process.whereis(Sensitivity), do: Sensitivity.level(), else: default_sensitivity_level()
  end

  @doc """
  Set detection sensitivity on every configured sensor using the UI scale.

  `level` is `1..9` where **1 = least sensitive** (fewer phantoms) and
  **9 = most sensitive** (longer reach, more clutter). The mapping to the
  device register is defined by `Octopus.Radar.SensorType` for each sensor
  type.

  Internally this re-runs the full init sequence with the new value, so
  the device's tracker state is reset along with the parameter change.
  Not persisted across restarts. Broadcasts to all radar LiveViews immediately.
  """
  @spec set_sensitivity_level(1..9) :: :ok
  def set_sensitivity_level(level) when is_integer(level) and level in 1..9 do
    Sensitivity.set_level(level)

    Enum.each(sensor_configs(), fn {device_id, config} ->
      type = Keyword.fetch!(config, :type)
      set_sensitivity(device_id, SensorType.level_to_device_value(type, level))
    end)

    broadcast_sensitivity_level_changed(level)
    :ok
  end

  @doc false
  @spec set_sensitivity(pos_integer(), pos_integer()) :: :ok | {:error, term()}
  def set_sensitivity(device_id, device_value) when is_integer(device_value) do
    Sensor.set_sensitivity(device_id, device_value)
  end

  @doc "Shared radar LiveView UI settings (north panel, list mode, visuals, …)."
  @spec view_settings() :: ViewSettings.t()
  def view_settings do
    if Process.whereis(ViewSettings), do: ViewSettings.get(), else: default_view_settings()
  end

  @doc "Runtime north-panel index for circular ring rendering."
  @spec north_panel() :: pos_integer()
  def north_panel do
    if Process.whereis(ViewSettings), do: ViewSettings.north_panel(), else: Octopus.Installation.north_panel()
  end

  @spec set_north_panel(pos_integer()) :: :ok
  def set_north_panel(panel) when is_integer(panel) and panel >= 1 do
    ViewSettings.set_north_panel(panel)
    broadcast_view_settings_changed()
    :ok
  end

  @spec set_detection_list_mode(ViewSettings.detection_list_mode()) :: :ok
  def set_detection_list_mode(mode) when mode in [:by_sensor, :by_proximity] do
    ViewSettings.set_detection_list_mode(mode)
    broadcast_view_settings_changed()
    :ok
  end

  @spec toggle_coords_frame() :: ViewSettings.coords_frame()
  def toggle_coords_frame do
    frame = ViewSettings.toggle_coords_frame()
    broadcast_view_settings_changed()
    frame
  end

  @spec toggle_visual(atom()) :: :ok | :error
  def toggle_visual(key) when is_atom(key) do
    case ViewSettings.toggle_visual(key) do
      :ok ->
        broadcast_view_settings_changed()
        :ok

      :error ->
        :error
    end
  end

  @spec set_bounds_mode(ViewSettings.bounds_mode()) :: :ok
  def set_bounds_mode(mode) when mode in [:static, :auto] do
    ViewSettings.set_bounds_mode(mode)
    broadcast_view_settings_changed()
    :ok
  end

  @doc """
  Re-run the full init sequence on a sensor, resetting all internal
  tracker state on the device. Useful when track ids have drifted into
  high values or when the operator wants a clean slate.
  """
  @spec reinitialize(pos_integer()) :: :ok | {:error, term()}
  def reinitialize(device_id), do: Sensor.reinitialize(device_id)

  @doc """
  Return `true` when the active installation defines a `:radar` configuration.

  When `false`, the radar supervisor is not started and sensor APIs are inert.
  Use `source_mode/0` to turn sensors on or off at runtime when configured.
  """
  @spec configured?() :: boolean()
  def configured? do
    Octopus.Installation.radar_config() != nil
  end

  @doc """
  Return `true` when this host has deployment bindings for every logical
  sensor in the active installation (Live mode can talk to real hardware).
  """
  @spec live_available?() :: boolean()
  def live_available? do
    configured?() and
      SensorPlan.deployment_bound?(Octopus.Installation.radar_config(), deployment_config())
  end

  @doc """
  Return the sensor source mode to apply at boot, from `:boot_source_mode` in config.

  Defaults to `:off` in dev and `:live` in prod. Unlike `source_mode/0`, this reads
  config and is safe while building the supervision tree.
  """
  @spec boot_source_mode() :: SourceMode.t()
  def boot_source_mode do
    case Application.get_env(:octopus, __MODULE__, []) |> Keyword.get(:boot_source_mode, :off) do
      mode when mode in [:off, :live, :exact, :fuzzy] -> mode
      _ -> :off
    end
  end

  @doc """
  Return the current radar source mode.

    * `:off`   — no sensor processes; radar UI/config only
    * `:live`  — real sensors on serial ports (when deployment-bound)
    * `:exact` — mock sensors with perfect synthetic detections
    * `:fuzzy` — mock sensors with noise and dropout
  """
  @spec source_mode() :: SourceMode.t()
  def source_mode do
    case Process.whereis(SourceMode) do
      nil -> boot_source_mode()
      _pid -> SourceMode.get()
    end
  end

  @doc """
  Return the active mock-world simulation mode (`:exact`, `:fuzzy`, or `:off`).

  `:off` when the source is `:off` or `:live`.
  """
  @spec mock_mode() :: :off | :exact | :fuzzy
  def mock_mode do
    case source_mode() do
      mode when mode in [:exact, :fuzzy] -> mode
      _ -> :off
    end
  end

  @doc """
  Switch the radar source mode at runtime.

  Tears down and restarts sensors as needed. Broadcasts
  `{:source_mode_changed, mode}` on `topic/0`.
  """
  @spec set_source_mode(SourceMode.t()) :: :ok
  def set_source_mode(:off), do: do_set_source_mode(:off)

  def set_source_mode(:live) do
    if live_available?(), do: do_set_source_mode(:live), else: :ok
  end

  def set_source_mode(mode) when mode in [:exact, :fuzzy], do: do_set_source_mode(mode)

  @doc "Deprecated — use `set_source_mode/1`."
  @spec set_mock_mode(:off | :exact | :fuzzy) :: :ok
  def set_mock_mode(:off), do: set_source_mode(:live)
  def set_mock_mode(mode) when mode in [:exact, :fuzzy], do: set_source_mode(mode)

  defp do_set_source_mode(mode) do
    SourceMode.set(mode)
    Mock.World.set_mode(mock_world_mode(mode))
    restart_all_sensors(mode)
    Phoenix.PubSub.broadcast(Octopus.PubSub, topic(), {:source_mode_changed, mode})
    :ok
  end

  defp mock_world_mode(mode) when mode in [:exact, :fuzzy], do: mode
  defp mock_world_mode(_), do: :off

  @doc "Current mock-world population cap. See `Octopus.Radar.Mock.World`."
  @spec max_people() :: pos_integer()
  def max_people do
    case Process.whereis(Mock.World) do
      nil -> 0
      _pid -> Mock.World.max_people()
    end
  end

  @doc "Set the mock-world population cap (`1..max_people_limit/0`)."
  @spec set_max_people(integer()) :: :ok
  def set_max_people(n) when is_integer(n) do
    case Process.whereis(Mock.World) do
      nil ->
        :ok

      _pid ->
        Mock.World.set_max_people(n)
        broadcast_mock_settings_changed()
    end
  end

  # Each physical HLK-LD6001A can track up to ~10 people, so the simulated
  # world is capped at this many per configured sensor.
  @per_sensor_detection_cap 10

  @doc """
  Upper bound for the mock-world population cap: `@per_sensor_detection_cap`
  detectable people per logical sensor in the installation (e.g. 6 sensors → 60).
  Derived from installation config so it is safe during `Mock.World` boot.
  """
  @spec max_people_limit() :: pos_integer()
  def max_people_limit do
    count =
      case Octopus.Installation.radar_config() do
        nil ->
          1

        radar ->
          radar
          |> Keyword.fetch!(:layout)
          |> Keyword.fetch!(:sensors)
          |> length()
      end

    max(count, 1) * @per_sensor_detection_cap
  end

  @doc "Radius (meters) of the simulated mock world. See `Octopus.Radar.Mock.World`."
  @spec world_radius_m() :: float()
  def world_radius_m do
    case Process.whereis(Mock.World) do
      nil -> default_world_radius_m()
      _pid -> Mock.World.radius_m()
    end
  end

  defp default_world_radius_m do
    if Octopus.Installation.arrangement() == :circular do
      Octopus.Installation.ring_radius_m()
    else
      8.0
    end
  end

  @doc "Current mock-world activity level (0..100). See `Octopus.Radar.Mock.World`."
  @spec entropy() :: 0..100
  def entropy do
    case Process.whereis(Mock.World) do
      nil -> 50
      _pid -> Mock.World.entropy()
    end
  end

  @doc "Set the mock-world activity level (0..100)."
  @spec set_entropy(integer()) :: :ok
  def set_entropy(n) when is_integer(n) do
    case Process.whereis(Mock.World) do
      nil ->
        :ok

      _pid ->
        Mock.World.set_entropy(n)
        broadcast_mock_settings_changed()
    end
  end

  @doc "Whether mock manual (cursor-driven) tracking is on. See `Octopus.Radar.Mock.World`."
  @spec manual_tracking?() :: boolean()
  def manual_tracking? do
    case Process.whereis(Mock.World) do
      nil -> false
      _pid -> Mock.World.manual?()
    end
  end

  @doc "Enable/disable mock manual (cursor-driven) tracking."
  @spec set_manual_tracking(boolean()) :: :ok
  def set_manual_tracking(enabled) when is_boolean(enabled) do
    case Process.whereis(Mock.World) do
      nil ->
        :ok

      _pid ->
        Mock.World.set_manual(enabled)
        broadcast_mock_settings_changed()
    end
  end

  @doc "Place the manually-tracked mock object at `{x, y}` (global meters)."
  @spec set_manual_point(number(), number()) :: :ok
  def set_manual_point(x, y) when is_number(x) and is_number(y) do
    case Process.whereis(Mock.World) do
      nil -> :ok
      _pid -> Mock.World.set_manual_point(x, y)
    end
  end

  @doc "Remove the manually-tracked mock object."
  @spec clear_manual_point() :: :ok
  def clear_manual_point do
    case Process.whereis(Mock.World) do
      nil -> :ok
      _pid -> Mock.World.clear_manual_point()
    end
  end

  @doc """
  Return the live status of a single sensor.

    * `:inactive`     — toggled off at runtime by the operator (process stopped)
    * `:unavailable`  — active but port cannot be opened; retrying every 5 s
    * `:initializing` — port open, AT init command sequence in progress
    * `:working`      — fully initialised and publishing frames
    * `:stale`        — port open but no frames received recently; device may
                        be disconnected at the UART/sensor level (distinct from
                        `:unavailable` which means the USB-serial port itself
                        cannot be opened)

  Config-disabled sensors (`enabled: false`) are excluded from the UI
  entirely and never queried here. The sensor GenServer is looked up via
  the Registry; the call returns immediately.
  """
  @spec sensor_status(pos_integer()) ::
          :inactive | :unavailable | :probing | :initializing | :working | :stale
  def sensor_status(device_id) do
    cond do
      not configured?() -> :inactive
      not Runtime.enabled?(device_id) -> :inactive
      true ->
        case Sensor.get_ui_status(device_id) do
          {:ok, status} -> status
          {:error, _} -> :unavailable
        end
    end
  end

  @doc "PubSub topic for status-change broadcasts of a single sensor."
  @spec status_topic(pos_integer()) :: String.t()
  def status_topic(device_id) when is_integer(device_id) and device_id >= 1,
    do: "#{topic(device_id)}:status"

  @doc "Subscribe to status-change broadcasts for a single sensor."
  @spec subscribe_status(pos_integer()) :: :ok | {:error, term()}
  def subscribe_status(device_id),
    do: Phoenix.PubSub.subscribe(Octopus.PubSub, status_topic(device_id))

  @doc "Broadcast a sensor status change. Called internally by `Octopus.Radar.Sensor`."
  @spec broadcast_status(pos_integer(), atom()) :: :ok | {:error, term()}
  def broadcast_status(device_id, status) do
    Phoenix.PubSub.broadcast(
      Octopus.PubSub,
      status_topic(device_id),
      {:radar_sensor_status, device_id, status}
    )
  end

  @doc "Return the full 60-second status history for all sensors: `%{device_id => [{ms, status}]}`."
  @spec get_history() :: %{pos_integer() => [{integer(), atom()}]}
  defdelegate get_history(), to: Octopus.Radar.StatusHistory, as: :get_all

  @doc "Return the 60-second status history for one sensor: `[{ms, status}]`, newest-first."
  @spec get_history(pos_integer()) :: [{integer(), atom()}]
  defdelegate get_history(device_id), to: Octopus.Radar.StatusHistory

  @doc "Return in-memory operational statistics for all sensors. See `Octopus.Radar.Stats`."
  @spec get_stats() :: %{pos_integer() => map()}
  defdelegate get_stats(), to: Octopus.Radar.Stats, as: :get_all

  @doc "Reset all sensor statistics counters."
  @spec reset_stats() :: :ok
  defdelegate reset_stats(), to: Octopus.Radar.Stats, as: :reset

  @doc """
  Return `true` when the active radar setup uses a `:radial` layout block.

  Runtime pose sliders in the radar UI are only shown in this configuration.
  """
  @spec radial_layout?() :: boolean()
  def radial_layout? do
    configured?() and radial_layout_config?()
  end

  @doc """
  Starting bearing (degrees) for the first sensor in a radial layout.

  Reads the runtime tweak when present, otherwise the value from config.
  """
  @spec layout_start_angle_deg() :: number()
  def layout_start_angle_deg do
    cond do
      Process.whereis(PoseTweak) -> PoseTweak.layout_start_angle_deg()
      radial_layout_config?() -> config_layout_start_angle_deg()
      true -> 0
    end
  end

  @doc """
  Global offset (degrees) added to every sensor's `:angle_deg` at runtime.

  Used to rotate the installation coordinate frame without reassigning ports.
  """
  @spec angle_offset_deg() :: number()
  def angle_offset_deg do
    if Process.whereis(PoseTweak), do: PoseTweak.angle_offset_deg(), else: 0
  end

  @doc """
  Set the radial layout's starting angle (which port sits at which bearing).

  Not persisted across restarts. Updates live sensor pose configs immediately.
  """
  @spec set_layout_start_angle_deg(number()) :: :ok
  def set_layout_start_angle_deg(deg) when is_number(deg) do
    PoseTweak.set_layout_start_angle_deg(deg)
    apply_pose_tweaks()
    broadcast_pose_tweak_changed()
    :ok
  end

  @doc """
  Set a global offset applied to every sensor's `:angle_deg`.

  Not persisted across restarts. Updates live sensor pose configs immediately.
  """
  @spec set_angle_offset_deg(number()) :: :ok
  def set_angle_offset_deg(deg) when is_number(deg) do
    PoseTweak.set_angle_offset_deg(deg)
    apply_pose_tweaks()
    broadcast_pose_tweak_changed()
    :ok
  end

  @doc """
  Enable a sensor at runtime, starting its process if not already running.

  This overrides an `enabled: false` config entry for the current runtime
  session. The change is not persisted across restarts.
  """
  @spec enable_sensor(pos_integer()) :: :ok | {:error, term()}
  def enable_sensor(device_id) do
    Runtime.set(device_id, true)

    case sensor_configs() |> Enum.find(fn {id, _} -> id == device_id end) do
      nil ->
        {:error, :not_configured}

      {_, config} ->
        # Start fresh from a clean slate so the right transport (real vs mock)
        # is used for the current mock mode.
        stop_sensor_children(device_id)
        start_sensor_children(device_id, config, source_mode())
        :ok
    end
  end

  @doc """
  Disable a sensor at runtime, stopping and removing its process.

  This is the inverse of `enable_sensor/1`. In mock mode it also stops the
  paired fake device. The change is not persisted across restarts.
  """
  @spec disable_sensor(pos_integer()) :: :ok | {:error, term()}
  def disable_sensor(device_id) do
    Runtime.set(device_id, false)
    stop_sensor_children(device_id)
    broadcast_status(device_id, :inactive)
    :ok
  end

  @doc """
  Return `true` if at least one configured sensor's serial port currently
  exists on disk.
  """
  @spec any_present?() :: boolean()
  def any_present? do
    sensor_configs()
    |> Enum.any?(fn {_id, config} ->
      Keyword.fetch!(config, :enabled) and File.exists?(Keyword.fetch!(config, :port))
    end)
  end

  ## Supervisor

  def start_link(_opts) do
    Supervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    boot = boot_source_mode()
    log_boot_configuration(boot)

    children =
      [
        {SourceMode, boot},
        {Registry, keys: :unique, name: Octopus.Radar.Registry},
        {Runtime, initial_runtime_for(boot)},
        {PoseTweak, []},
        {Sensitivity, []},
        {ViewSettings, []},
        Octopus.Radar.StatusHistory,
        Octopus.Radar.Stats,
        {Mock.World, [mode: mock_world_mode(boot)]}
      ] ++ sensor_children(boot)

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp initial_runtime_for(:off), do: %{}

  defp initial_runtime_for(boot) when boot in [:live, :exact, :fuzzy] do
    sensor_configs_for(boot)
    |> Enum.filter(fn {_, cfg} -> Keyword.fetch!(cfg, :enabled) end)
    |> Map.new(fn {id, _} -> {id, true} end)
  end

  defp sensor_children(:off), do: []

  defp sensor_children(boot) do
    missing_at_boot =
      if boot == :live do
        sensor_configs_for(:live)
        |> Enum.filter(fn {_id, cfg} ->
          Keyword.fetch!(cfg, :enabled) and not File.exists?(Keyword.fetch!(cfg, :port))
        end)
      else
        []
      end

    if missing_at_boot != [] do
      Logger.info(
        "[radar] #{length(missing_at_boot)} sensor(s) waiting for serial port at boot"
      )
    end

    sensor_configs_for(boot)
    |> Enum.flat_map(fn {device_id, config} ->
      port = Keyword.fetch!(config, :port)
      enabled? = Keyword.fetch!(config, :enabled)

      cond do
        not enabled? ->
          Logger.debug("#{LogFormat.tag(device_id, port)} Sensor disabled in config — skipping")
          []

        true ->
          device_child_specs(device_id, config, boot)
      end
    end)
  end

  # Child specs for one device under the current source mode.
  defp device_child_specs(device_id, config, mode) do
    case Keyword.fetch!(config, :type) do
      :ld6001a ->
        sensor_child_specs(device_id, config, mode)

      type ->
        Logger.warning(
          "#{LogFormat.tag(device_id, Keyword.fetch!(config, :port))} Unknown sensor type #{inspect(type)} — skipping"
        )

        []
    end
  end

  defp sensor_child_specs(device_id, config, :live) do
    [sensor_spec(device_id, config, [])]
  end

  defp sensor_child_specs(_device_id, _config, :off), do: []

  defp sensor_child_specs(device_id, config, mode) when mode in [:exact, :fuzzy] do
    mock_spec =
      Supervisor.child_spec(
        {Mock.Server,
         [device_id: device_id, config: config, mode: mode, name: mock_via(device_id)]},
        id: {Mock.Server, device_id}
      )

    sensor =
      sensor_spec(device_id, config,
        transport: Octopus.Radar.Transport.Mock,
        transport_opts: [server: mock_via(device_id)]
      )

    [mock_spec, sensor]
  end

  defp sensor_spec(device_id, config, extra) do
    opts =
      config
      |> Keyword.put(:device_id, device_id)
      |> Keyword.merge(extra)

    Supervisor.child_spec({Sensor, opts}, id: {Sensor, device_id})
  end

  defp mock_via(device_id),
    do: {:via, Registry, {Octopus.Radar.Registry, {:mock, device_id}}}

  # Tear down and restart every runtime-enabled sensor for a mode switch.
  defp restart_all_sensors(:off) do
    logical_device_ids()
    |> Enum.each(fn device_id ->
      Runtime.set(device_id, false)
      stop_sensor_children(device_id)
    end)
  end

  defp restart_all_sensors(mode) when mode in [:live, :exact, :fuzzy] do
    if mode in [:exact, :fuzzy, :live] do
      sensor_configs()
      |> Enum.each(fn {device_id, config} ->
        if Keyword.fetch!(config, :enabled), do: Runtime.set(device_id, true)
      end)
    end

    logical_device_ids()
    |> Enum.each(&stop_sensor_children/1)

    sensor_configs()
    |> Enum.each(fn {device_id, config} ->
      if Keyword.fetch!(config, :enabled) and Runtime.enabled?(device_id) do
        start_sensor_children(device_id, config, mode)
      end
    end)
  end

  defp start_sensor_children(device_id, config, mode) do
    device_child_specs(device_id, config, mode)
    |> Enum.each(fn spec ->
      case Supervisor.start_child(__MODULE__, spec) do
        {:ok, _} -> :ok
        {:error, {:already_started, _}} -> :ok
        {:error, :already_present} -> :ok
        error -> Logger.warning("#{LogFormat.device_letter(device_id)} start_child failed: #{inspect(error)}")
      end
    end)
  end

  defp stop_sensor_children(device_id) do
    for child_id <- [{Sensor, device_id}, {Mock.Server, device_id}] do
      case Supervisor.terminate_child(__MODULE__, child_id) do
        :ok -> Supervisor.delete_child(__MODULE__, child_id)
        _ -> :ok
      end
    end

    :ok
  end

  defp log_boot_configuration(boot) do
    configs = sensor_configs_for(boot)

    case configs do
      [] ->
        case boot do
          :off -> Logger.info("[radar] Enabled — source off (no sensors)")
          _ -> Logger.info("[radar] Enabled — no sensors configured")
        end

      _ ->
        summary =
          configs
          |> Enum.map(fn {id, cfg} ->
            status =
              if Keyword.fetch!(cfg, :enabled), do: "enabled", else: "disabled"

            pose =
              "pose=#{Keyword.fetch!(cfg, :angle_deg)}°/#{Keyword.fetch!(cfg, :distance_cm)}cm/r#{Keyword.fetch!(cfg, :rotation_deg)}°"

            port = Keyword.fetch!(cfg, :port)
            "#{LogFormat.device_letter(id)} #{LogFormat.short_port(port)} (#{status}, #{pose})"
          end)
          |> Enum.join("; ")

        Logger.info("[radar] Enabled — #{length(configs)} sensor(s): #{summary}")
    end
  end

  ## Configuration helpers

  @doc false
  @spec sensor_configs() :: [{pos_integer(), keyword()}]
  def sensor_configs do
    if configured?(), do: do_sensor_configs(), else: []
  end

  defp do_sensor_configs do
    do_sensor_configs_for(source_mode())
  end

  defp do_sensor_configs_for(:off), do: []

  defp do_sensor_configs_for(mode) do
    installation_radar = Octopus.Installation.radar_config()
    deployment = deployment_config()

    cond do
      is_nil(installation_radar) ->
        []

      mode == :live and not SensorPlan.deployment_bound?(installation_radar, deployment) ->
        []

      true ->
        SensorPlan.build(installation_radar, deployment, mode)
    end
  end

  # Build sensor configs for a specific source mode (used at boot before the
  # SourceMode agent reflects runtime changes).
  defp sensor_configs_for(mode), do: if(configured?(), do: do_sensor_configs_for(mode), else: [])

  defp logical_device_ids do
    case Octopus.Installation.radar_config() do
      nil ->
        []

      radar ->
        radar
        |> Keyword.fetch!(:layout)
        |> Keyword.fetch!(:sensors)
        |> Enum.with_index(1)
        |> Enum.map(fn {_, device_id} -> device_id end)
    end
  end

  defp deployment_config do
    Application.get_env(:octopus, :radar_deployment)
  end

  defp installation_layout do
    case Octopus.Installation.radar_config() do
      nil -> []
      radar -> Keyword.get(radar, :layout, [])
    end
  end

  defp radial_layout_config? do
    Keyword.get(installation_layout(), :type) == :radial
  end

  defp config_layout_start_angle_deg do
    (installation_layout() |> Keyword.get(:start_angle_deg, 0)) * 1.0
  end

  defp apply_pose_tweaks do
    sensor_configs()
    |> Enum.each(fn {device_id, config} ->
      Sensor.update_config(device_id, config)
      update_mock_config(device_id, config)
    end)
  end

  defp update_mock_config(device_id, config) do
    try do
      Mock.Server.update_config(mock_via(device_id), config)
    catch
      :exit, {:noproc, _} -> :ok
    end
  end

  defp broadcast_pose_tweak_changed do
    Phoenix.PubSub.broadcast(
      Octopus.PubSub,
      topic(),
      {:pose_tweak_changed,
       %{
         layout_start_angle_deg: layout_start_angle_deg(),
         angle_offset_deg: angle_offset_deg()
       }}
    )
  end

  defp broadcast_sensitivity_level_changed(level) do
    Phoenix.PubSub.broadcast(Octopus.PubSub, topic(), {:sensitivity_level_changed, level})
  end

  defp broadcast_view_settings_changed do
    Phoenix.PubSub.broadcast(Octopus.PubSub, topic(), {:view_settings_changed, view_settings()})
  end

  defp broadcast_mock_settings_changed do
    Phoenix.PubSub.broadcast(
      Octopus.PubSub,
      topic(),
      {:mock_settings_changed,
       %{
         max_people: max(max_people(), 1),
         entropy: entropy(),
         manual_tracking: manual_tracking?()
       }}
    )
  end

  defp default_sensitivity_level do
    with radar when not is_nil(radar) <- Octopus.Installation.radar_config(),
         defaults <- Keyword.get(radar, :defaults, []),
         setting <- Keyword.get(defaults, :sensitivity, SensorType.default_sensitivity_setting()),
         device_value <- SensorType.resolve_sensitivity(:ld6001a, setting) do
      SensorType.sensitivity_level(:ld6001a, device_value)
    else
      _ -> 6
    end
  end

  defp default_view_settings do
    %ViewSettings{
      north_panel: Octopus.Installation.north_panel(),
      detection_list_mode: :by_sensor,
      coords_frame: :global,
      visuals: ViewSettings.default_visuals(),
      bounds_mode: :static
    }
  end
end
