defmodule Octopus.Radar.SensorPlan do
  @moduledoc false
  # Merges installation logical sensor layout with deployment hardware bindings.

  alias Octopus.Radar.{Deployment, PoseTweak, SensorType}

  @global_defaults [
    type: :ld6001a,
    enabled: true,
    angle_deg: 0,
    distance_cm: 0,
    rotation_deg: 0,
    baud: 115_200,
    sensitivity: :normal,
    height_cm: 500,
    range_cm: 500,
    x_pos_cm: 500,
    x_neg_cm: -500,
    y_pos_cm: 500,
    y_neg_cm: -500,
    moving_decisecs: 110,
    static_decisecs: 100,
    exit_decisecs: 5
  ]

  @layout_geometry_keys [:type, :sensors, :start_angle_deg]
  @supported_types [:ld6001a]
  @deployment_binding_keys [:port]
  @per_sensor_installation_keys [
    :angle_deg,
    :distance_cm,
    :rotation_deg,
    :height_cm,
    :range_cm,
    :x_pos_cm,
    :x_neg_cm,
    :y_pos_cm,
    :y_neg_cm,
    :moving_decisecs,
    :static_decisecs,
    :exit_decisecs,
    :sensitivity,
    :enabled,
    :type
  ]

  @doc """
  Normalizes installation layout `:sensors` to `{id, keyword}` tuples.

  Each entry may be a sensor id atom or `[id: :a, rotation_deg: 5, ...]`.
  """
  @spec normalize_sensor_entries(list()) :: [{atom(), keyword()}]
  def normalize_sensor_entries(sensors) when is_list(sensors) do
    Enum.map(sensors, &normalize_sensor_entry/1)
  end

  @doc "Returns sensor ids from a layout `:sensors` list, in installation order."
  @spec sensor_ids(list()) :: [atom()]
  def sensor_ids(sensors) when is_list(sensors) do
    sensors |> normalize_sensor_entries() |> Enum.map(fn {id, _} -> id end)
  end

  @doc false
  @spec validate_sensor_entries!(list()) :: :ok
  def validate_sensor_entries!(sensors) do
    unless is_list(sensors) and sensors != [] do
      raise ArgumentError, "radar layout :sensors must be a non-empty list"
    end

    entries = normalize_sensor_entries(sensors)
    ids = Enum.map(entries, fn {id, _} -> id end)

    unless Enum.all?(ids, &is_atom/1) do
      raise ArgumentError, "radar layout :sensors ids must be atoms, got #{inspect(sensors)}"
    end

    if length(ids) != length(Enum.uniq(ids)) do
      raise ArgumentError, "radar layout :sensors contains duplicate ids: #{inspect(ids)}"
    end

    Enum.each(entries, fn {_id, opts} ->
      unknown = Keyword.keys(opts) -- @per_sensor_installation_keys

      unless unknown == [] do
        raise ArgumentError,
              "radar layout sensor entry has unsupported keys #{inspect(unknown)}; " <>
                "allowed: #{inspect(@per_sensor_installation_keys)}"
      end
    end)

    :ok
  end

  defp normalize_sensor_entry(id) when is_atom(id), do: {id, []}

  defp normalize_sensor_entry(opts) when is_list(opts) do
    id =
      case Keyword.fetch(opts, :id) do
        {:ok, sensor_id} when is_atom(sensor_id) ->
          sensor_id

        _ ->
          raise ArgumentError,
                "radar layout sensor entry must include atom :id, got #{inspect(opts)}"
      end

    {id, Keyword.delete(opts, :id)}
  end

  defp normalize_sensor_entry(other) do
    raise ArgumentError,
          "radar layout :sensors entries must be atoms or keyword lists, got #{inspect(other)}"
  end

  @doc """
  Returns sensor configs as `{device_id, keyword}` in installation sensor order.

  `installation_radar` comes from `Octopus.Installation.radar_config/0`.
  `deployment` is the active deployment keyword list (may be `nil`).
  `plan_mode` is `:live`, `:exact`, or `:fuzzy`.
  """
  @spec build(keyword() | nil, keyword() | nil, :live | :exact | :fuzzy) ::
          [{pos_integer(), keyword()}]
  def build(nil, _deployment, _plan_mode), do: []

  def build(installation_radar, deployment, plan_mode) do
    layout = Keyword.fetch!(installation_radar, :layout)
    sensor_entries = layout |> Keyword.fetch!(:sensors) |> normalize_sensor_entries()
    pose_list = expand_layout(layout, length(sensor_entries))
    bindings = bindings_by_id(deployment)

    unless length(pose_list) == length(sensor_entries) do
      raise ArgumentError,
            "radar layout :sensors has #{length(sensor_entries)} ids but generated #{length(pose_list)} poses"
    end

    inst_defaults = Keyword.merge(@global_defaults, Keyword.get(installation_radar, :defaults, []))
    layout_defaults = Keyword.drop(layout, @layout_geometry_keys)
    deploy_defaults = if deployment, do: Keyword.get(deployment, :defaults, []), else: []
    merged_defaults = inst_defaults |> Keyword.merge(layout_defaults) |> Keyword.merge(deploy_defaults)

    sensor_entries
    |> Enum.zip(pose_list)
    |> Enum.with_index(1)
    |> Enum.map(fn {{{sensor_id, sensor_opts}, base_pose}, device_id} ->
      pose_opts = Keyword.merge(base_pose, sensor_opts)
      port_opts = resolve_binding(sensor_id, device_id, Map.get(bindings, sensor_id), plan_mode)

      config =
        merged_defaults
        |> Keyword.merge(pose_opts)
        |> Keyword.merge(port_opts)
        |> Keyword.put(:sensor_id, sensor_id)
        |> maybe_apply_pose_tweaks(layout, device_id)
        |> normalize_sensor_config(device_id)

      {device_id, config}
    end)
  end

  @doc "True when every installation sensor id has a deployment port binding."
  @spec deployment_bound?(keyword() | nil, keyword() | nil) :: boolean()
  def deployment_bound?(nil, _deployment), do: false

  def deployment_bound?(installation_radar, deployment) do
    sensor_ids =
      installation_radar
      |> Keyword.fetch!(:layout)
      |> Keyword.fetch!(:sensors)
      |> sensor_ids()

    bindings = bindings_by_id(deployment)

    deployment != nil and
      Enum.all?(sensor_ids, fn id ->
        case Map.get(bindings, id) do
          nil -> false
          opts -> Keyword.get(opts, :port) not in [nil, ""]
        end
      end)
  end

  defp bindings_by_id(nil), do: %{}

  defp bindings_by_id(deployment) do
    registry = Deployment.port_registry(deployment)

    deployment
    |> Keyword.get(:sensors, [])
    |> Map.new(fn opts ->
      id = Keyword.fetch!(opts, :id)

      resolved =
        case Deployment.resolve_port(opts, registry) do
          {:ok, port} ->
            opts
            |> Keyword.drop([:id])
            |> Keyword.put(:port, port)

          {:error, _} ->
            Keyword.drop(opts, [:id])
        end

      {id, resolved}
    end)
  end

  defp resolve_binding(sensor_id, device_id, binding, plan_mode) when is_list(binding) do
    case Keyword.get(binding, :port) do
      port when is_binary(port) and port != "" ->
        connection_opts(binding)

      _ ->
        resolve_binding(sensor_id, device_id, nil, plan_mode)
    end
  end

  defp resolve_binding(_sensor_id, device_id, _binding, plan_mode)
       when plan_mode in [:exact, :fuzzy] do
    [port: "/dev/tty.mock-radar-#{device_id}", type: :ld6001a]
  end

  defp resolve_binding(sensor_id, device_id, _binding, :live) do
    [port: "/dev/tty.unbound-#{device_id}", type: :ld6001a, sensor_id: sensor_id]
  end

  defp expand_layout(layout, sensor_count) do
    case Keyword.fetch!(layout, :type) do
      :radial -> expand_radial(layout, sensor_count)
      other -> raise ArgumentError, "radar layout: unsupported :type #{inspect(other)}"
    end
  end

  defp expand_radial(layout, count) do
    unless count > 0 do
      raise ArgumentError, "radar layout :sensors must be a non-empty list"
    end

    start_angle = effective_layout_start_angle(layout)
    step = 360.0 / count

    # Sensor ids are placed in list order clockwise around the ring.
    Enum.map(0..(count - 1), fn i ->
      [angle_deg: PoseTweak.normalize_deg(start_angle - i * step)]
    end)
  end

  defp connection_opts(binding) do
    binding
    |> Keyword.drop([:id])
    |> Keyword.take(@deployment_binding_keys)
  end

  defp effective_layout_start_angle(layout) do
    if Process.whereis(PoseTweak) do
      PoseTweak.layout_start_angle_deg()
    else
      Keyword.get(layout, :start_angle_deg, 0) * 1.0
    end
  end

  defp maybe_apply_pose_tweaks(config, layout, device_id) do
    if Keyword.get(layout, :type) == :radial do
      config
      |> apply_global_rotation_offset()
      |> apply_sensor_installation_angle(device_id)
    else
      config
    end
  end

  defp apply_global_rotation_offset(config) do
    rotation =
      config
      |> Keyword.get(:rotation_deg, 0)
      |> Kernel.+(effective_angle_offset())
      |> PoseTweak.normalize_deg()

    Keyword.put(config, :rotation_deg, rotation)
  end

  defp apply_sensor_installation_angle(config, device_id) do
    rotation =
      config
      |> Keyword.get(:rotation_deg, 0)
      |> Kernel.+(effective_sensor_installation_angle(device_id))
      |> PoseTweak.normalize_deg()

    Keyword.put(config, :rotation_deg, rotation)
  end

  defp effective_angle_offset do
    if Process.whereis(PoseTweak), do: PoseTweak.angle_offset_deg(), else: 0.0
  end

  defp effective_sensor_installation_angle(device_id) do
    if Process.whereis(PoseTweak), do: PoseTweak.sensor_installation_angle_deg(device_id), else: 0.0
  end

  defp normalize_sensor_config(config, device_id) do
    type = Keyword.fetch!(config, :type)
    sensitivity_setting = Keyword.fetch!(config, :sensitivity)
    enabled = Keyword.fetch!(config, :enabled)
    angle_deg = Keyword.fetch!(config, :angle_deg)
    distance_cm = Keyword.fetch!(config, :distance_cm)
    rotation_deg = Keyword.fetch!(config, :rotation_deg)

    unless type in @supported_types do
      raise ArgumentError,
            "radar sensor ##{device_id}: unsupported type #{inspect(type)}"
    end

    unless is_boolean(enabled) do
      raise ArgumentError, "radar sensor ##{device_id}: :enabled must be a boolean"
    end

    unless is_number(angle_deg) and angle_deg >= 0 and angle_deg <= 360 do
      raise ArgumentError, "radar sensor ##{device_id}: :angle_deg must be in 0..360"
    end

    unless is_number(distance_cm) and distance_cm >= 0 do
      raise ArgumentError, "radar sensor ##{device_id}: :distance_cm must be >= 0"
    end

    unless is_number(rotation_deg) do
      raise ArgumentError, "radar sensor ##{device_id}: :rotation_deg must be a number"
    end

    config
    |> Keyword.put(:sensitivity, SensorType.resolve_sensitivity(type, sensitivity_setting))
  end
end
