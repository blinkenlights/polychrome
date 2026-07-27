defmodule Octopus.Osc.UiSync do
  @moduledoc """
  Build OSC messages that mirror the Pixel Fun 3D performance bank
  (plus global speed) for TouchOSC feedback.
  """

  alias OSCx.Message
  alias Octopus.Apps.PixelFun3D
  alias Octopus.InstallationTransport
  alias Octopus.Params.Global

  @continuous [
    :brightness_percent,
    :zoom_base,
    :roll_rate,
    :orbit_rate,
    :elev_base,
    :tilt_scale,
    :saturation_percent,
    :color_interval,
    :bleeding
  ]

  @discrete [:time_frozen, :time_direction]

  def continuous_keys, do: @continuous
  def discrete_keys, do: @discrete
  def takeover_keys, do: [:global_speed | @continuous]

  @doc """
  Snapshot of values to push. `tweaks` is nil when PixelFun3D is not live.
  """
  def snapshot do
    case InstallationTransport.get_state() do
      %{now_playing: %{app: PixelFun3D, effective: eff}} when is_map(eff) ->
        %{global_speed: Global.speed(), tweaks: Map.take(eff, @continuous ++ @discrete)}

      _ ->
        %{global_speed: Global.speed(), tweaks: nil}
    end
  end

  def snapshot_from_public(%{now_playing: %{app: PixelFun3D, effective: eff}}) when is_map(eff) do
    %{global_speed: Global.speed(), tweaks: Map.take(eff, @continuous ++ @discrete)}
  end

  def snapshot_from_public(_), do: %{global_speed: Global.speed(), tweaks: nil}

  @doc """
  Encode snapshot as OSC messages (App units).
  """
  def messages(%{global_speed: speed, tweaks: nil}) do
    [%Message{address: "/global/speed", arguments: [osc_float(speed)]}]
  end

  def messages(%{global_speed: speed, tweaks: tweaks}) when is_map(tweaks) do
    continuous =
      Enum.map(@continuous, fn key ->
        %Message{
          address: "/pixelfun3d/#{key}",
          arguments: [osc_number(key, Map.get(tweaks, key))]
        }
      end)

    discrete = [
      %Message{
        address: "/pixelfun3d/time_frozen",
        arguments: [osc_bool(Map.get(tweaks, :time_frozen))]
      },
      %Message{
        address: "/pixelfun3d/time_direction",
        arguments: [osc_direction(Map.get(tweaks, :time_direction))]
      }
    ]

    [%Message{address: "/global/speed", arguments: [osc_float(speed)]}] ++ continuous ++ discrete
  end

  defp osc_number(key, value)
       when key in [:brightness_percent, :saturation_percent, :bleeding] and is_number(value) do
    trunc(value) * 1.0
  end

  defp osc_number(_key, value) when is_number(value), do: value * 1.0
  defp osc_number(_key, _), do: 0.0

  defp osc_float(value) when is_number(value), do: value * 1.0
  defp osc_float(_), do: 1.0

  defp osc_bool(true), do: 1.0
  defp osc_bool(false), do: 0.0
  defp osc_bool(_), do: 0.0

  defp osc_direction(:backward), do: "backward"
  defp osc_direction("backward"), do: "backward"
  defp osc_direction(_), do: "forward"
end
