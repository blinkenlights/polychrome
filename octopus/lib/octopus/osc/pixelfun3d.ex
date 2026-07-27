defmodule Octopus.Osc.Pixelfun3D do
  @moduledoc """
  OSC ingress for Pixel Fun 3D performance controls.

  Routes `/pixelfun3d/<tweakable>` through `InstallationTransport.set_tweakable/2`
  (same path as the installation console). Legacy Params keys
  (`time_scale`, `easing_interval`, `value_percent`) stay on `Octopus.Params`.
  """

  require Logger

  alias Octopus.Apps.PixelFun3D
  alias Octopus.InstallationTransport

  @legacy_params ~w(time_scale easing_interval value_percent)

  @tweakables ~w(
    brightness_percent
    zoom_base
    roll_rate
    orbit_rate
    elev_base
    tilt_scale
    saturation_percent
    color_interval
    bleeding
    time_frozen
    time_direction
  )

  @integer_sliders MapSet.new(~w(brightness_percent saturation_percent))

  @doc """
  Handle OSC path segments after `/pixelfun3d`.

  Returns:
  - `:handled` — tweakable applied via InstallationTransport
  - `:legacy` — fall through to Params.put
  - `:ignored` — PixelFun3D not now-playing (or empty args)
  - `:unknown` — not a Slice-1 address
  """
  def handle([key], args) when key in @legacy_params and is_list(args) do
    :legacy
  end

  def handle([key], args) when key in @tweakables and is_list(args) do
    case pixelfun3d_live?() do
      true ->
        case normalize_arg(key, args) do
          {:ok, value} ->
            InstallationTransport.set_tweakable(String.to_existing_atom(key), value)
            :handled

          :error ->
            Logger.warning("OSC /pixelfun3d/#{key} bad args: #{inspect(args)}")
            :ignored
        end

      false ->
        Logger.debug("OSC /pixelfun3d/#{key} ignored: PixelFun3D is not now-playing")
        :ignored
    end
  end

  def handle(_rest, _args), do: :unknown

  @doc false
  def tweakables, do: @tweakables

  @doc false
  def legacy_params, do: @legacy_params

  @doc """
  Normalize a raw OSC argument list into a transport-friendly value.
  """
  def normalize_arg("time_frozen", args) do
    case unwrap(args) do
      v when v in [true, "true", "1", 1, 1.0] -> {:ok, 1}
      v when v in [false, "false", "0", 0, 0.0] -> {:ok, 0}
      _ -> :error
    end
  end

  def normalize_arg("time_direction", args) do
    case unwrap(args) do
      dir when dir in ["forward", "backward"] -> {:ok, dir}
      :forward -> {:ok, "forward"}
      :backward -> {:ok, "backward"}
      _ -> :error
    end
  end

  def normalize_arg(key, args) when is_binary(key) do
    case unwrap(args) do
      value when is_number(value) ->
        if MapSet.member?(@integer_sliders, key) do
          {:ok, trunc(value)}
        else
          {:ok, value * 1.0}
        end

      value when is_binary(value) ->
        case Float.parse(value) do
          {n, _} ->
            if MapSet.member?(@integer_sliders, key) do
              {:ok, trunc(n)}
            else
              {:ok, n}
            end

          :error ->
            :error
        end

      _ ->
        :error
    end
  end

  defp unwrap([value]), do: value
  defp unwrap([value | _]), do: value
  defp unwrap(value), do: value

  defp pixelfun3d_live? do
    case InstallationTransport.get_state() do
      %{live: %{app: PixelFun3D}} -> true
      %{now_playing: %{app: PixelFun3D}} -> true
      _ -> false
    end
  end
end
