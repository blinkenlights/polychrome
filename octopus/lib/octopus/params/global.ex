defmodule Octopus.Params.Global do
  use Octopus.Params, prefix: :global

  @speed_min 0.01
  @speed_max 10.0
  @speed_slider_steps 1000

  def brightness, do: param(:brightness, 128)
  def speed, do: param(:speed, 1.0)
  def auto_brightness, do: param(:auto_brightness, false)
  def bleeding, do: param(:bleeding, 0.0)

  def speed_min, do: @speed_min
  def speed_max, do: @speed_max
  def speed_slider_steps, do: @speed_slider_steps

  def speed_to_slider(speed) when is_number(speed) do
    speed = clamp_speed(speed)
    ratio = :math.log(speed / @speed_min) / :math.log(@speed_max / @speed_min)
    round(ratio * @speed_slider_steps)
  end

  def slider_to_speed(slider) when is_number(slider) do
    t = slider |> max(0) |> min(@speed_slider_steps)
    @speed_min * :math.pow(@speed_max / @speed_min, t / @speed_slider_steps) |> clamp_speed()
  end

  def format_speed(speed) when is_number(speed) do
    speed = clamp_speed(speed)

    cond do
      speed >= 10 -> "10"
      speed >= 1 -> speed |> Float.round(2) |> trim_trailing_zeros()
      speed >= 0.1 -> speed |> Float.round(2) |> trim_trailing_zeros()
      true -> speed |> Float.round(3) |> trim_trailing_zeros()
    end
  end

  @doc """
  Config schema for web UI - similar to app config schemas
  """
  def config_schema do
    %{
      brightness: {"Brightness", :int, %{default: 128, min: 0, max: 255}},
      speed: {"Speed", :exp_float, %{default: 1.0, min: @speed_min, max: @speed_max}},
      auto_brightness: {"Auto Brightness", :boolean, %{default: false}},
      bleeding: {"Bleeding", :float, %{default: 0.0, min: 0.0, max: 100.0, step: 1.0}}
    }
  end

  @doc """
  Get current global config for web UI
  """
  def config do
    %{
      brightness: brightness(),
      speed: speed(),
      auto_brightness: auto_brightness(),
      bleeding: bleeding()
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
        :bleeding -> handle_param("bleeding", [value])
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
    clamped_value = clamp_speed(value)
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

  def handle_param("bleeding", [value]) when is_number(value) do
    clamped_value = value |> max(0.0) |> min(100.0)

    Phoenix.PubSub.broadcast(
      Octopus.PubSub,
      "global_params",
      {:param_updated, :bleeding, clamped_value}
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

  defp clamp_speed(speed), do: speed |> max(@speed_min) |> min(@speed_max)

  defp trim_trailing_zeros(value) when is_float(value) do
    value
    |> :erlang.float_to_binary(decimals: 6)
    |> String.trim_trailing("0")
    |> String.trim_trailing(".")
  end
end
