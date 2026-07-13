defmodule Octopus.Radar.ViewSettings do
  @moduledoc false
  use Agent

  @default_visuals %{
    world_border: true,
    platform: true,
    ring_panels: true,
    coverage: true,
    placements: true,
    persons: true,
    detections: true,
    trails: true,
    arrows: false,
    height_size: true,
    labels: true,
    ruler: true
  }

  @type detection_list_mode :: :by_sensor | :by_proximity
  @type coords_frame :: :global | :local
  @type bounds_mode :: :static | :auto

  defstruct [
    :north_panel,
    :detection_list_mode,
    :coords_frame,
    :visuals,
    :bounds_mode
  ]

  @type t :: %__MODULE__{
          north_panel: pos_integer(),
          detection_list_mode: detection_list_mode(),
          coords_frame: coords_frame(),
          visuals: %{atom() => boolean()},
          bounds_mode: bounds_mode()
        }

  def start_link(_opts) do
    Agent.start_link(fn -> initial_state() end, name: __MODULE__)
  end

  @spec default_visuals() :: %{atom() => boolean()}
  def default_visuals, do: @default_visuals

  @spec get() :: t()
  def get, do: Agent.get(__MODULE__, & &1)

  @spec north_panel() :: pos_integer()
  def north_panel, do: Agent.get(__MODULE__, & &1.north_panel)

  @spec detection_list_mode() :: detection_list_mode()
  def detection_list_mode, do: Agent.get(__MODULE__, & &1.detection_list_mode)

  @spec coords_frame() :: coords_frame()
  def coords_frame, do: Agent.get(__MODULE__, & &1.coords_frame)

  @spec visuals() :: %{atom() => boolean()}
  def visuals, do: Agent.get(__MODULE__, & &1.visuals)

  @spec bounds_mode() :: bounds_mode()
  def bounds_mode, do: Agent.get(__MODULE__, & &1.bounds_mode)

  @spec set_north_panel(pos_integer()) :: :ok
  def set_north_panel(panel) when is_integer(panel) and panel >= 1 do
    Agent.update(__MODULE__, &%{&1 | north_panel: clamp_north_panel(panel)})
  end

  @spec set_detection_list_mode(detection_list_mode()) :: :ok
  def set_detection_list_mode(mode) when mode in [:by_sensor, :by_proximity] do
    Agent.update(__MODULE__, &%{&1 | detection_list_mode: mode})
  end

  @spec set_coords_frame(coords_frame()) :: :ok
  def set_coords_frame(frame) when frame in [:global, :local] do
    Agent.update(__MODULE__, &%{&1 | coords_frame: frame})
  end

  @spec toggle_coords_frame() :: coords_frame()
  def toggle_coords_frame do
    Agent.get_and_update(__MODULE__, fn state ->
      frame = if state.coords_frame == :local, do: :global, else: :local
      {frame, %{state | coords_frame: frame}}
    end)
  end

  @spec toggle_visual(atom()) :: :ok | :error
  def toggle_visual(key) when is_atom(key) do
    case Agent.get(__MODULE__, &Map.has_key?(&1.visuals, key)) do
      true ->
        Agent.update(__MODULE__, fn state ->
          %{state | visuals: Map.update!(state.visuals, key, &(!&1))}
        end)

        :ok

      false ->
        :error
    end
  end

  @spec set_bounds_mode(bounds_mode()) :: :ok
  def set_bounds_mode(mode) when mode in [:static, :auto] do
    Agent.update(__MODULE__, &%{&1 | bounds_mode: mode})
  end

  defp initial_state do
    %__MODULE__{
      north_panel: Octopus.Installation.north_panel(),
      detection_list_mode: :by_sensor,
      coords_frame: :global,
      visuals: @default_visuals,
      bounds_mode: :static
    }
  end

  defp clamp_north_panel(panel) do
    max_panels =
      case Octopus.Installation.arrangement() do
        :circular -> max(Octopus.Installation.num_panels(), 1)
        _ -> 1
      end

    panel |> max(1) |> min(max_panels)
  end
end
