defmodule Octopus.Radar do
  @moduledoc """
  Public facade and supervisor for the HLK-LD6001A-60G radar layer.

  This module both supervises one `Octopus.Radar.Sensor` per configured
  device and exposes the consumer-facing API for subscribing to tracking
  data.

  ## Configuration

  Configured under the `:octopus, Octopus.Radar` key in `config/config.exs`:

      config :octopus, Octopus.Radar,
        sensors: [
          [port: "/dev/tty.usbserial-0001"],   # device_id 1
          [port: "/dev/tty.usbserial-0002"]    # device_id 2
        ],
        defaults: [
          baud: 921_600,
          height_cm: 300, range_cm: 450,
          x_pos_cm: 450, x_neg_cm: -450,
          y_pos_cm: 450, y_neg_cm: -450,
          moving_decisecs: 110, static_decisecs: 100, exit_decisecs: 5
        ]

  The integer **`device_id` is the 1-based position** of an entry in the
  `:sensors` list and is used both to register the sensor process and as
  the tag in PubSub messages.

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

  alias Octopus.Radar.Sensor

  @topic "radar:hlk6001"

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
            port: String.t(),
            baud: pos_integer(),
            sensitivity: 1..9,
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
        port: Keyword.fetch!(config, :port),
        baud: Keyword.fetch!(config, :baud),
        sensitivity: Keyword.fetch!(config, :sensitivity),
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
  Return `true` if at least one configured sensor's serial port currently
  exists. Used by `Octopus.Application` to decide whether to add the
  radar supervisor to the supervision tree.
  """
  @spec any_present?() :: boolean()
  def any_present? do
    sensor_configs()
    |> Enum.any?(fn {_id, config} -> File.exists?(Keyword.fetch!(config, :port)) end)
  end

  ## Supervisor

  def start_link(_opts) do
    Supervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    children =
      [{Registry, keys: :unique, name: Octopus.Radar.Registry}] ++
        sensor_children()

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp sensor_children do
    sensor_configs()
    |> Enum.flat_map(fn {device_id, config} ->
      port = Keyword.fetch!(config, :port)

      if File.exists?(port) do
        [
          Supervisor.child_spec(
            {Sensor, Keyword.put(config, :device_id, device_id)},
            id: {Sensor, device_id}
          )
        ]
      else
        Logger.warning(
          "[radar #{device_id} #{port}] Configured port not present at boot — skipping"
        )

        []
      end
    end)
  end

  ## Configuration helpers

  @doc false
  @spec sensor_configs() :: [{pos_integer(), keyword()}]
  def sensor_configs do
    radar_env = Application.get_env(:octopus, __MODULE__, [])
    defaults = Keyword.get(radar_env, :defaults, [])
    sensors = Keyword.get(radar_env, :sensors, [])

    sensors
    |> Enum.with_index(1)
    |> Enum.map(fn {sensor_opts, index} ->
      {index, Keyword.merge(defaults, sensor_opts)}
    end)
  end
end
