defmodule Octopus.Radar.TrackFusion do
  @moduledoc """
  System-level cross-sensor track fusion toggle/threshold.

  When enabled, `Octopus.Radar.fuse_people/1` combines duplicate detections of
  the same real-world object reported by different radar devices into one
  "combined object" (see `Octopus.Radar.TrackMerge`), within `radius_m`. This
  is shared by every consumer (`PanelActivity`, `PanelGravity`, the radar live
  view) so they all agree on what counts as one object — an object that drifts
  in and out of a second sensor's field of view shouldn't make gravity/activity
  jump as the detection count changes underneath it.

  Disabling fusion falls back to raw, unmerged per-sensor tracks everywhere.
  """
  use Agent

  @default_enabled? true
  @default_radius_m 2.0
  @min_radius_m 0.1
  @max_radius_m 5.0

  defstruct enabled?: @default_enabled?, radius_m: @default_radius_m

  @type t :: %__MODULE__{enabled?: boolean(), radius_m: float()}

  def start_link(_opts) do
    Agent.start_link(fn -> %__MODULE__{} end, name: __MODULE__)
  end

  @spec get() :: t()
  def get, do: Agent.get(__MODULE__, & &1)

  @spec enabled?() :: boolean()
  def enabled?, do: Agent.get(__MODULE__, & &1.enabled?)

  @spec radius_m() :: float()
  def radius_m, do: Agent.get(__MODULE__, & &1.radius_m)

  @spec set_enabled(boolean()) :: :ok
  def set_enabled(enabled?) when is_boolean(enabled?) do
    Agent.update(__MODULE__, &%{&1 | enabled?: enabled?})
  end

  @spec toggle_enabled() :: boolean()
  def toggle_enabled do
    Agent.get_and_update(__MODULE__, fn state ->
      enabled? = not state.enabled?
      {enabled?, %{state | enabled?: enabled?}}
    end)
  end

  @spec set_radius_m(number()) :: :ok
  def set_radius_m(radius_m) when is_number(radius_m) do
    Agent.update(__MODULE__, &%{&1 | radius_m: clamp_radius(radius_m)})
  end

  defp clamp_radius(radius_m) when is_number(radius_m) do
    radius_m |> max(@min_radius_m) |> min(@max_radius_m)
  end
end
