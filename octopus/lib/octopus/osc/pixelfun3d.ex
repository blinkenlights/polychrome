defmodule Octopus.Osc.Pixelfun3D do
  @moduledoc """
  OSC ingress for Pixel Fun 3D performance controls.

  Routes `/pixelfun3d/<tweakable>` through `InstallationTransport.set_tweakable/2`
  (same path as the installation console). Continuous controls use soft takeover.
  Scene fire and panic use transport `play_now` / tweakables. Legacy Params keys
  (`time_scale`, `easing_interval`, `value_percent`) stay on `Octopus.Params`.
  """

  require Logger

  alias Octopus.AppModePresets
  alias Octopus.Apps.PixelFun3D
  alias Octopus.InstallationTransport
  alias Octopus.Osc.SoftTakeover

  @legacy_params ~w(time_scale easing_interval value_percent)

  @continuous ~w(
    brightness_percent
    zoom_base
    roll_rate
    orbit_rate
    elev_base
    tilt_scale
    saturation_percent
    color_interval
    bleeding
  )

  @discrete ~w(time_frozen time_direction)

  @tweakables @continuous ++ @discrete

  @integer_sliders MapSet.new(~w(brightness_percent saturation_percent))

  # Curated TouchOSC bank (Phase 1); server accepts any known pixelfun3d slug.
  @live_bank ~w(
    classic_ripple
    nordlicht
    doppelhelix
    leuchtplankton
    sternenhimmel
    marmor
    strudel
    nebelringe
  )

  @autos_off %{
    trans_auto: false,
    rot_auto: false,
    zoom_auto: false,
    sway_auto: false,
    sat_auto: false
  }

  @panic_motion %{
    time_frozen: true,
    roll_rate: 0.0,
    orbit_rate: 0.0,
    elev_base: 0.0,
    tilt_scale: 0.0
  }

  @doc """
  Handle OSC path segments after `/pixelfun3d`.

  `client` identifies the OSC peer for soft-takeover state (`{ip, port}` or `:local`).

  Returns:
  - `:handled` — action applied
  - `:held` — soft takeover waiting for pickup
  - `:legacy` — fall through to Params.put
  - `:ignored` — not applicable / bad trigger / unknown slug
  - `:unknown` — not a supported address
  """
  def handle(rest, args, client \\ :local)

  def handle([key], args, _client) when key in @legacy_params and is_list(args) do
    :legacy
  end

  def handle([key], args, client) when key in @continuous and is_list(args) do
    case pixelfun3d_live?() do
      true ->
        case normalize_arg(key, args) do
          {:ok, value} ->
            atom = String.to_existing_atom(key)
            actual = current_tweakable(atom)

            if SoftTakeover.accept?(client, atom, value, actual) do
              InstallationTransport.set_tweakable(atom, value)
              :handled
            else
              :held
            end

          :error ->
            Logger.warning("OSC /pixelfun3d/#{key} bad args: #{inspect(args)}")
            :ignored
        end

      false ->
        Logger.debug("OSC /pixelfun3d/#{key} ignored: PixelFun3D is not now-playing")
        :ignored
    end
  end

  def handle([key], args, client) when key in @discrete and is_list(args) do
    case pixelfun3d_live?() do
      true ->
        case normalize_arg(key, args) do
          {:ok, value} ->
            atom = String.to_existing_atom(key)
            SoftTakeover.mark_matched(client, atom)
            InstallationTransport.set_tweakable(atom, value)
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

  def handle(["panic"], args, _client) when is_list(args) do
    if trigger?(args) do
      panic()
    else
      :ignored
    end
  end

  def handle(["scenes", slug, "fire"], args, _client)
      when is_binary(slug) and is_list(args) do
    if trigger?(args) do
      fire_scene(slug)
    else
      :ignored
    end
  end

  def handle(["config"], args, _client) when is_list(args) do
    if trigger?(args), do: :sync, else: :ignored
  end

  def handle(_rest, _args, _client), do: :unknown

  @doc false
  def tweakables, do: @tweakables

  @doc false
  def continuous, do: @continuous

  @doc false
  def legacy_params, do: @legacy_params

  @doc false
  def live_bank, do: @live_bank

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

  defp fire_scene(slug) do
    mode_id = AppModePresets.mode_id(PixelFun3D, slug)

    if known_mode?(mode_id) do
      case InstallationTransport.play_now(PixelFun3D, mode_id) do
        :ok ->
          # Re-fire same scene clears live overrides; new scene is already clean.
          InstallationTransport.discard_now_playing_overrides()
          # Force motion/sat autos off; palette_auto stays as in the preset.
          InstallationTransport.set_tweakables(@autos_off)
          :handled

        {:error, reason} ->
          Logger.warning("OSC scene fire #{mode_id} failed: #{inspect(reason)}")
          :ignored
      end
    else
      Logger.warning("OSC scene fire unknown slug: #{inspect(slug)}")
      :ignored
    end
  end

  defp panic do
    if pixelfun3d_live?() do
      InstallationTransport.set_tweakables(Map.merge(@panic_motion, @autos_off))
      :handled
    else
      Logger.debug("OSC /pixelfun3d/panic ignored: PixelFun3D is not now-playing")
      :ignored
    end
  end

  defp current_tweakable(key) do
    case InstallationTransport.get_state() do
      %{now_playing: %{app: PixelFun3D, effective: eff}} when is_map(eff) ->
        Map.get(eff, key)

      _ ->
        nil
    end
  end

  defp known_mode?(mode_id) do
    config = PixelFun3D.mode_config(mode_id)
    is_map(config) and map_size(config) > 0
  end

  defp trigger?([]), do: true

  defp trigger?(args) do
    case unwrap(args) do
      v when v in [true, "true", "1", 1, 1.0] -> true
      _ -> false
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
