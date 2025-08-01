defmodule Octopus.Params.Global do
  use Octopus.Params, prefix: :global

  def brightness, do: param(:brightness, 128)
  def speed, do: param(:speed, 1.0)
  def auto_brightness, do: param(:auto_brightness, false)

  @doc """
  Config schema for web UI - similar to app config schemas
  """
  def config_schema do
    %{
      brightness: {"Global Brightness", :int, %{default: 128, min: 0, max: 255}},
      speed: {"Animation Speed", :float, %{default: 1.0, min: 0.1, max: 2.0, step: 0.1}},
      auto_brightness: {"Auto Brightness", :boolean, %{default: false}}
    }
  end

  @doc """
  Get current global config for web UI
  """
  def config do
    %{
      brightness: brightness(),
      speed: speed(),
      auto_brightness: auto_brightness()
    }
  end

  @doc """
  Update global parameters from web UI
  """
  def update_config(config) do
    Enum.each(config, fn {key, value} ->
      case key do
        :brightness -> handle_param("brightness", [value])
        :speed -> handle_param("speed", [value])
        :auto_brightness -> handle_param("auto_brightness", [value])
        _ -> :ignore
      end

      # Also store in params system
      Octopus.Params.put("global", Atom.to_string(key), value)

      # Broadcast parameter change for UI updates
      Phoenix.PubSub.broadcast(Octopus.PubSub, "global_params", {:param_updated, key, value})
    end)
  end

  @doc """
  Subscribe to global parameter changes
  """
  def subscribe do
    Phoenix.PubSub.subscribe(Octopus.PubSub, "global_params")
  end

  def handle_param("brightness", [value]) when is_number(value) do
    clamped_value = value |> min(255) |> max(0)

    # Only apply manual brightness changes if auto-brightness is disabled
    if not auto_brightness() do
      Octopus.Broadcaster.set_luminance(clamped_value)
    end

    # Always broadcast for UI sync (so the parameter gets stored and UI updates)
    Phoenix.PubSub.broadcast(
      Octopus.PubSub,
      "global_params",
      {:param_updated, :brightness, clamped_value}
    )
  end

  def handle_param("speed", [value]) when is_number(value) do
    clamped_value = value |> min(2.0) |> max(0.1)
    # Speed parameter stored - could be used by animations for time scaling
    # Value is automatically stored in params system via put_param_and_reply

    # Broadcast for UI sync (OSC changes should update web UI)
    Phoenix.PubSub.broadcast(
      Octopus.PubSub,
      "global_params",
      {:param_updated, :speed, clamped_value}
    )

    :ok
  end

  def handle_param("auto_brightness", [value]) when is_boolean(value) do
    # When auto-brightness is toggled, we need to restart/stop the sunlight service
    # For now, just broadcast the change - the sunlight service will handle restart logic

    # Broadcast for UI sync
    Phoenix.PubSub.broadcast(
      Octopus.PubSub,
      "global_params",
      {:param_updated, :auto_brightness, value}
    )

    # Also broadcast on sunlight topic for service restart
    Phoenix.PubSub.broadcast(
      Octopus.PubSub,
      "sunlight:config",
      {:auto_brightness_changed, value}
    )

    :ok
  end

  def handle_param(_key, _value) do
    # ignore
  end
end
