defmodule Octopus.Params.Launchpad do
  @moduledoc """
  Persisted settings for the optional Launchpad Mini MK3 colour output
  (see `Octopus.Outputs.LaunchpadMini`).
  """

  use Octopus.Params, prefix: :launchpad

  @brightness_min 0
  @brightness_max 127

  def brightness, do: param(:brightness, 100)

  def brightness_min, do: @brightness_min
  def brightness_max, do: @brightness_max

  @doc """
  Config schema for web UI - similar to the app config schemas.
  """
  def config_schema do
    %{
      brightness:
        {"Brightness", :int, %{default: 100, min: @brightness_min, max: @brightness_max}}
    }
  end

  @doc """
  Get current Launchpad config for web UI.
  """
  def config do
    %{
      brightness: brightness()
    }
  end

  @doc """
  Update Launchpad parameters from web UI.
  """
  def update_config(config) do
    Enum.each(config, fn {key, value} ->
      case key do
        :brightness -> handle_param("brightness", [value])
        _ -> :ignore
      end

      Octopus.Params.put("launchpad", Atom.to_string(key), value)

      Phoenix.PubSub.broadcast(Octopus.PubSub, "launchpad_params", {:param_updated, key, value})
    end)
  end

  @doc """
  Subscribe to Launchpad parameter changes.
  """
  def subscribe do
    Phoenix.PubSub.subscribe(Octopus.PubSub, "launchpad_params")
  end

  def handle_param("brightness", [value]) when is_number(value) do
    clamped_value = value |> min(@brightness_max) |> max(@brightness_min)

    Octopus.Outputs.LaunchpadMini.set_brightness(clamped_value)

    Phoenix.PubSub.broadcast(
      Octopus.PubSub,
      "launchpad_params",
      {:param_updated, :brightness, clamped_value}
    )
  end

  def handle_param(_key, _value) do
    :ignore
  end
end
