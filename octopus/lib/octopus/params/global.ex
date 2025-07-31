defmodule Octopus.Params.Global do
  use Octopus.Params, prefix: :global

  def brightness, do: param(:brightness, 128)
  def speed, do: param(:speed, 1.0)

  @doc """
  Config schema for web UI - similar to app config schemas
  """
  def config_schema do
    %{
      brightness: {"Global Brightness", :int, %{default: 128, min: 0, max: 255}},
      speed: {"Animation Speed", :float, %{default: 1.0, min: 0.1, max: 2.0, step: 0.1}}
    }
  end

  @doc """
  Get current global config for web UI
  """
  def config do
    %{
      brightness: brightness(),
      speed: speed()
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
    Octopus.Broadcaster.set_luminance(clamped_value)

    # Broadcast for UI sync (OSC changes should update web UI)
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

  def handle_param(_key, _value) do
    # ignore
  end
end
