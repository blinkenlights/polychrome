defmodule Octopus.Radar do
  @moduledoc """
  Public facade and supervisor for the HLK-LD6001A-60G radar layer.

  This module both supervises one `Octopus.Radar.Sensor` per configured
  device and exposes the consumer-facing API for subscribing to tracking
  data.

  ## Configuration

  Loaded at runtime from `config/radar.exs` (via `config/runtime.exs`), with
  optional per-machine overrides in `config/radar.local.exs` (dev, gitignored)
  or `/data/radar.local.exs` (Docker deployments).

  Two configuration styles are supported: **manual** and **layout**.

  ### Manual style

      config :octopus, Octopus.Radar,
        enabled: true,
        sensors: [
          [port: "/dev/ttyUSB0", enabled: true, angle_deg: 0, distance_cm: 150, rotation_deg: 0],
          [port: "/dev/ttyUSB1", angle_deg: 60, distance_cm: 150, rotation_deg: 180]
        ],
        defaults: [
          type: :ld6001a,
          enabled: true,
          rotation_deg: 180,
          baud: 115_200,
          height_cm: 300, range_cm: 450,
          x_pos_cm: 450, x_neg_cm: -450,
          y_pos_cm: 450, y_neg_cm: -450,
          moving_decisecs: 110, static_decisecs: 100, exit_decisecs: 5
        ]

  ### Layout style

  For uniform radial installations (sensors evenly spaced around a central
  mast) use `:layout` + `:ports` instead of `:sensors`. The layout generates
  `angle_deg` automatically; all other sensor parameters come from the
  non-geometry keys inside the `:layout` block or from a `:defaults` block.

      config :octopus, Octopus.Radar,
        layout: [
          type: :radial,           # only supported layout type
          count: 6,                # number of sensors
          start_angle_deg: 0,      # bearing of first sensor
          distance_cm: 150,        # mount distance from center (shared)
          rotation_deg: 180,       # 0 = outward, 180 = inward (shared)
          height_cm: 300,
          sensitivity: 4
        ],
        ports: [
          "/dev/ttyUSB0",          # paired with first auto-generated angle
          "/dev/ttyUSB1",
          [port: "/dev/ttyUSB2", rotation_deg: 182]  # per-port override
        ]

  A `:ports` entry may be a plain string or a keyword list with `:port` plus
  any per-sensor overrides that take precedence over layout/defaults values.

  `:layout` and `:sensors` are mutually exclusive; an error is raised if both
  are present.

  ### Pose parameters

  `rotation_deg` is **relative to the outward beam direction** (`angle_deg`).
  The effective global rotation applied to local coordinates is
  `angle_deg + rotation_deg`. Common values:

    * `0` — sensor's local +X aligned with the beam pointing away from center
    * `180` — sensor facing inward toward center

  This allows a single `rotation_deg` default to cover all sensors in a
  uniform array, with small per-sensor corrections for physical misalignment.

  * `:enabled` — master switch; when `false`, no supervisor or serial I/O.
    Overridable via `RADAR_ENABLED` (`true`/`1`/`yes` vs anything else).

  The integer **`device_id` is the 1-based position** of an entry in the
  `:sensors` (or `:ports`) list and is used both to register the sensor
  process and as the tag in PubSub messages.

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

  alias Octopus.Radar.{Runtime, Sensor}

  @topic "radar:hlk6001"
  @supported_types [:ld6001a]
  @default_pose [
    type: :ld6001a,
    enabled: true,
    angle_deg: 0,
    distance_cm: 0,
    rotation_deg: 0
  ]

  ## Public API

  @doc "Global PubSub topic — fan-in of frames from all sensors."
  @spec topic() :: String.t()
  def topic, do: @topic

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
  Return a list describing each configured sensor in `device_id` order.

  Includes sensors whose port does not currently exist; consult `:port`
  with `File.exists?/1` if the caller cares about presence.

  The reported `sensitivity` is the configured DPKTH value at boot
  (range 1..9, where lower means *more* sensitive); it does not track
  runtime changes made via `set_sensitivity/2`. The `*_cm` values are
  the device's geometry parameters as configured (see `AT+XPosi` &c.
  in the manual / `Octopus.Radar.Command`).
  """
  @spec devices() :: [
          %{
            device_id: pos_integer(),
            type: atom(),
            enabled: boolean(),
            port: String.t(),
            baud: pos_integer(),
            sensitivity: 1..9,
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
    |> Enum.map(fn {device_id, config} ->
      %{
        device_id: device_id,
        type: Keyword.fetch!(config, :type),
        enabled: Keyword.fetch!(config, :enabled),
        port: Keyword.fetch!(config, :port),
        baud: Keyword.fetch!(config, :baud),
        sensitivity: Keyword.fetch!(config, :sensitivity),
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
    end)
  end

  @doc """
  Set the long-range detection sensitivity (`AT+DPKTH`) on a sensor.

  `level` is the device's raw scale: `1..9`, where **lower values mean
  more sensitive** (more phantom targets / longer reach) and higher
  values mean less sensitive. The default is `4`.

  Internally this re-runs the full init sequence with the new value, so
  the device's tracker state is reset along with the parameter change.
  """
  @spec set_sensitivity(pos_integer(), 1..9) :: :ok | {:error, term()}
  def set_sensitivity(device_id, level) when is_integer(level) and level in 1..9 do
    Sensor.set_sensitivity(device_id, level)
  end

  @doc """
  Re-run the full init sequence on a sensor, resetting all internal
  tracker state on the device. Useful when track ids have drifted into
  high values or when the operator wants a clean slate.
  """
  @spec reinitialize(pos_integer()) :: :ok | {:error, term()}
  def reinitialize(device_id), do: Sensor.reinitialize(device_id)

  @doc """
  Return `true` if the radar layer is enabled in application config.

  See `config/radar.exs` and optional `RADAR_ENABLED` / `config/radar.local.exs`.
  """
  @spec enabled?() :: boolean()
  def enabled? do
    Application.get_env(:octopus, __MODULE__, [])
    |> Keyword.get(:enabled, true)
  end

  @doc """
  Return the live status of a single sensor.

    * `:inactive`     — toggled off at runtime by the operator (process stopped)
    * `:unavailable`  — active but port cannot be opened; retrying every 5 s
    * `:initializing` — port open, AT init command sequence in progress
    * `:working`      — fully initialised and publishing frames

  Config-disabled sensors (`enabled: false`) are excluded from the UI
  entirely and never queried here. The sensor GenServer is looked up via
  the Registry; the call returns immediately.
  """
  @spec sensor_status(pos_integer()) :: :inactive | :unavailable | :initializing | :working
  def sensor_status(device_id) do
    if enabled?() and Runtime.enabled?(device_id) do
      case Sensor.get_phase(device_id) do
        {:ok, :running} -> :working
        {:ok, :configuring} -> :initializing
        {:ok, :opening} -> :unavailable
        {:error, _} -> :unavailable
      end
    else
      :inactive
    end
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
        child_spec =
          Supervisor.child_spec(
            {Sensor, Keyword.put(config, :device_id, device_id)},
            id: {Sensor, device_id}
          )

        case Supervisor.start_child(__MODULE__, child_spec) do
          {:ok, _} ->
            :ok

          {:error, {:already_started, _}} ->
            :ok

          {:error, :already_present} ->
            case Supervisor.restart_child(__MODULE__, {Sensor, device_id}) do
              {:ok, _} -> :ok
              error -> error
            end

          error ->
            error
        end
    end
  end

  @doc """
  Disable a sensor at runtime, stopping and removing its process.

  This is the inverse of `enable_sensor/1`. The change is not persisted
  across restarts.
  """
  @spec disable_sensor(pos_integer()) :: :ok | {:error, term()}
  def disable_sensor(device_id) do
    Runtime.set(device_id, false)

    case Supervisor.terminate_child(__MODULE__, {Sensor, device_id}) do
      :ok ->
        Supervisor.delete_child(__MODULE__, {Sensor, device_id})
        :ok

      {:error, :not_found} ->
        :ok

      error ->
        error
    end
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
    log_boot_configuration()

    # Only config-enabled sensors participate in the runtime active/inactive
    # toggle. Config-disabled sensors never appear in the UI and are not tracked.
    initial_runtime =
      sensor_configs()
      |> Enum.filter(fn {_, cfg} -> Keyword.fetch!(cfg, :enabled) end)
      |> Map.new(fn {id, _} -> {id, true} end)

    children =
      [
        {Registry, keys: :unique, name: Octopus.Radar.Registry},
        {Runtime, initial_runtime}
      ] ++ sensor_children()

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp sensor_children do
    sensor_configs()
    |> Enum.flat_map(fn {device_id, config} ->
      port = Keyword.fetch!(config, :port)
      enabled? = Keyword.fetch!(config, :enabled)

      cond do
        not enabled? ->
          Logger.info("[radar #{device_id} #{port}] Sensor disabled in config — skipping")
          []

        true ->
          if not File.exists?(port) do
            Logger.info(
              "[radar #{device_id} #{port}] Configured port not present at boot — starting sensor (will retry until available)"
            )
          end

          child_for_type(device_id, config)
      end
    end)
  end

  defp child_for_type(device_id, config) do
    case Keyword.fetch!(config, :type) do
      :ld6001a ->
        [
          Supervisor.child_spec(
            {Sensor, Keyword.put(config, :device_id, device_id)},
            id: {Sensor, device_id}
          )
        ]

      type ->
        Logger.warning(
          "[radar #{device_id} #{Keyword.fetch!(config, :port)}] Unknown sensor type #{inspect(type)} — skipping"
        )

        []
    end
  end

  defp log_boot_configuration do
    configs = sensor_configs()

    case configs do
      [] ->
        Logger.info("[radar] Enabled — no sensors configured")

      _ ->
        summary =
          configs
          |> Enum.map(fn {id, cfg} ->
            status =
              if Keyword.fetch!(cfg, :enabled), do: "enabled", else: "disabled"

            pose =
              "pose=#{Keyword.fetch!(cfg, :angle_deg)}°/#{Keyword.fetch!(cfg, :distance_cm)}cm/r#{Keyword.fetch!(cfg, :rotation_deg)}°"

            "##{id} #{Keyword.fetch!(cfg, :port)} (#{status}, #{pose})"
          end)
          |> Enum.join("; ")

        Logger.info("[radar] Enabled — #{length(configs)} sensor(s): #{summary}")
    end
  end

  ## Configuration helpers

  @doc false
  @spec sensor_configs() :: [{pos_integer(), keyword()}]
  def sensor_configs do
    if enabled?() do
      do_sensor_configs()
    else
      []
    end
  end

  defp do_sensor_configs do
    radar_env = Application.get_env(:octopus, __MODULE__, [])

    has_layout = Keyword.has_key?(radar_env, :layout)
    has_sensors = Keyword.has_key?(radar_env, :sensors)

    if has_layout and has_sensors do
      Logger.debug(
        "[radar] Both :layout and :sensors are set — :layout takes precedence " <>
          "(the base radar.exs :sensors list is the dev fallback and is ignored)"
      )
    end

    if has_layout do
      layout_sensor_configs(radar_env)
    else
      manual_sensor_configs(radar_env)
    end
  end

  defp manual_sensor_configs(radar_env) do
    defaults = Keyword.merge(@default_pose, Keyword.get(radar_env, :defaults, []))
    sensors = Keyword.get(radar_env, :sensors, [])

    sensors
    |> Enum.with_index(1)
    |> Enum.map(fn {sensor_opts, index} ->
      config =
        defaults
        |> Keyword.merge(sensor_opts)
        |> normalize_sensor_config(index)

      {index, config}
    end)
  end

  # Keys in a :layout block that describe the geometry and are NOT passed
  # through as per-sensor defaults.
  @layout_geometry_keys [:type, :count, :start_angle_deg]

  defp layout_sensor_configs(radar_env) do
    layout = Keyword.fetch!(radar_env, :layout)
    ports = Keyword.get(radar_env, :ports, [])

    layout_type = Keyword.get(layout, :type) ||
      raise ArgumentError, "radar layout: :type is required (e.g. type: :radial)"

    sensor_pose_list = expand_layout(layout_type, layout)

    unless length(sensor_pose_list) == length(ports) do
      raise ArgumentError,
            "radar layout: :ports has #{length(ports)} entries but layout generates " <>
              "#{length(sensor_pose_list)} sensors (count: #{Keyword.get(layout, :count)})"
    end

    defaults = Keyword.merge(@default_pose, Keyword.get(radar_env, :defaults, []))
    layout_defaults = Keyword.drop(layout, @layout_geometry_keys)
    merged_defaults = Keyword.merge(defaults, layout_defaults)

    sensor_pose_list
    |> Enum.zip(ports)
    |> Enum.with_index(1)
    |> Enum.map(fn {{pose_opts, port_entry}, index} ->
      port_opts = normalize_port_entry(port_entry)

      config =
        merged_defaults
        |> Keyword.merge(pose_opts)
        |> Keyword.merge(port_opts)
        |> normalize_sensor_config(index)

      {index, config}
    end)
  end

  defp expand_layout(:radial, layout) do
    count = Keyword.get(layout, :count) ||
      raise ArgumentError, "radar layout type :radial requires :count"

    unless is_integer(count) and count > 0 do
      raise ArgumentError,
            "radar layout: :count must be a positive integer, got #{inspect(count)}"
    end

    start_angle = Keyword.get(layout, :start_angle_deg, 0)
    step = 360.0 / count

    Enum.map(0..(count - 1), fn i ->
      [angle_deg: start_angle + i * step]
    end)
  end

  defp expand_layout(type, _layout) do
    raise ArgumentError,
          "radar layout: unsupported :type #{inspect(type)}; supported: [:radial]"
  end

  defp normalize_port_entry(port) when is_binary(port), do: [port: port]
  defp normalize_port_entry(opts) when is_list(opts), do: opts

  defp normalize_sensor_config(config, device_id) do
    type = Keyword.fetch!(config, :type)
    enabled = Keyword.fetch!(config, :enabled)
    angle_deg = Keyword.fetch!(config, :angle_deg)
    distance_cm = Keyword.fetch!(config, :distance_cm)
    rotation_deg = Keyword.fetch!(config, :rotation_deg)

    unless type in @supported_types do
      raise ArgumentError,
            "radar sensor ##{device_id}: unsupported type #{inspect(type)}, expected one of #{inspect(@supported_types)}"
    end

    unless is_boolean(enabled) do
      raise ArgumentError,
            "radar sensor ##{device_id}: :enabled must be a boolean, got #{inspect(enabled)}"
    end

    unless is_number(angle_deg) and angle_deg >= 0 and angle_deg <= 360 do
      raise ArgumentError,
            "radar sensor ##{device_id}: :angle_deg must be in 0..360, got #{inspect(angle_deg)}"
    end

    unless is_number(distance_cm) and distance_cm >= 0 do
      raise ArgumentError,
            "radar sensor ##{device_id}: :distance_cm must be >= 0, got #{inspect(distance_cm)}"
    end

    unless is_number(rotation_deg) do
      raise ArgumentError,
            "radar sensor ##{device_id}: :rotation_deg must be a number, got #{inspect(rotation_deg)}"
    end

    config
  end
end
